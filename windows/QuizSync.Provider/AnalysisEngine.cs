using System.Diagnostics;
using QuizSync.Core;
using QuizSync.Data;

namespace QuizSync.Provider;

/// <summary>一次识别的结果（缓存命中、解析失败、配额超限都从这里出去）。</summary>
public sealed record AnalysisOutcome(
    IReadOnlyList<Question> Questions,
    bool FromCache = false,
    string? CacheSessionId = null,
    string? RawText = null,
    bool ParseFailed = false,
    int LatencyMs = 0,
    string? ErrorCode = null,
    string? ErrorMessage = null,
    int ProviderCalls = 0)
{
    public bool Ok => ErrorCode is null && Questions.Count > 0;
}

/// <summary>
/// 识别的编排（`ai-contract.md` 第 3/4 节）：**缓存 → 配额 → 网络重试 → 容错解析 → 严格提醒重试 → 记录用量**。
///
/// 两条容易写错的语义：
/// - 缓存**只对单图**生效：多页组合无法用「第一页的哈希」区分后续页不同的两次识别，命中错缓存比不命中更糟；
/// - 解析失败后的「附加严格提醒再试一次」**不占网络重试预算**（那是两笔账）。
/// </summary>
public sealed class AnalysisEngine(
    IAiProvider provider,
    AnalysisCache cache,
    QuotaGuard quota,
    string deviceId,
    RetryPolicy? retry = null)
{
    private readonly RetryPolicy _retry = retry ?? new RetryPolicy();

    public Task<AnalysisOutcome> AnalyzeImageAsync(
        byte[] jpegBytes, string imageHash, AiConfig config, bool useCache = true, CancellationToken cancellationToken = default) =>
        AnalyzeImagesAsync([jpegBytes], imageHash, config, useCache, cancellationToken);

    public async Task<AnalysisOutcome> AnalyzeImagesAsync(
        IReadOnlyList<byte[]> pages, string imageHash, AiConfig config, bool useCache = true,
        CancellationToken cancellationToken = default)
    {
        if (pages.Count == 0)
        {
            return new AnalysisOutcome([], ErrorCode: "internal", ErrorMessage: "没有可分析的图片");
        }

        var promptVersion = Prompt.ComputePromptVersion();
        var cacheable = useCache && pages.Count == 1;

        // 1) 缓存命中 → 直接回放：不调 API、不占配额。
        if (cacheable)
        {
            var cached = cache.Lookup(imageHash, promptVersion, config.Model);
            if (cached is not null)
            {
                return new AnalysisOutcome(cached.Questions, FromCache: true, CacheSessionId: cached.SessionId);
            }
        }

        // 2) 每日配额。
        if (!quota.CanCall)
        {
            return new AnalysisOutcome([], ErrorCode: "ai_quota_exceeded", ErrorMessage: "今日调用已达上限，可在设置中调整");
        }

        // 3) 网络层重试（超时 / 连接失败 / 5xx / 429）。
        var stopwatch = Stopwatch.StartNew();
        var providerCalls = 0;
        try
        {
            var response = await _retry.ExecuteAsync(
                () =>
                {
                    providerCalls++;
                    return provider.AnalyzeAsync(pages, Prompt.AiPrompt, config, cancellationToken);
                },
                cancellationToken: cancellationToken).ConfigureAwait(false);

            var rawText = response.Text;

            // 4) 容错解析前 3 步；失败则附严格提醒再试 1 次（不占网络重试预算）。
            var json = ResponseParser.TryParseJson(rawText);
            if (json is null)
            {
                providerCalls++;
                var stricter = await provider
                    .AnalyzeAsync(pages, $"{Prompt.AiPrompt}\n\n{Prompt.StrictJsonReminder}", config, cancellationToken)
                    .ConfigureAwait(false);
                rawText = stricter.Text;
                json = ResponseParser.TryParseJson(rawText);
            }

            stopwatch.Stop();
            var latency = (int)stopwatch.ElapsedMilliseconds;

            if (json is null)
            {
                // 5) 保留原文供人工查看，并标记失败。
                quota.RecordUsage(config.Model, promptVersion, imageHash, ok: false, errorCode: "ai_bad_response", latencyMs: latency);
                return new AnalysisOutcome(
                    [], RawText: rawText, ParseFailed: true, LatencyMs: latency,
                    ErrorCode: "ai_bad_response", ErrorMessage: "AI 返回无法解析为 JSON，已保留原文",
                    ProviderCalls: providerCalls);
            }

            var parsed = ResponseParser.ToQuestions(json, sessionId: "pending", deviceId: deviceId, now: DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            quota.RecordUsage(config.Model, promptVersion, imageHash, ok: true, latencyMs: latency);

            return parsed.Questions.Count == 0
                ? new AnalysisOutcome(
                    [], RawText: rawText, LatencyMs: latency,
                    ErrorCode: "no_question_found", ErrorMessage: "未识别到题目", ProviderCalls: providerCalls)
                : new AnalysisOutcome(parsed.Questions, RawText: rawText, LatencyMs: latency, ProviderCalls: providerCalls);
        }
        catch (AiException error)
        {
            stopwatch.Stop();
            var latency = (int)stopwatch.ElapsedMilliseconds;
            var code = ErrorCodeFor(error);
            quota.RecordUsage(config.Model, promptVersion, imageHash, ok: false, errorCode: code, latencyMs: latency);
            return new AnalysisOutcome(
                [], LatencyMs: latency, ErrorCode: code, ErrorMessage: UserMessageFor(error), ProviderCalls: providerCalls);
        }
    }

    /// <summary>异常分类 → 客户端本地错误码（与 Dart 侧 `_errorCodeFor` 逐条一致）。</summary>
    public static string ErrorCodeFor(AiException error) => error.Kind switch
    {
        AiErrorKind.Timeout => "ai_timeout",
        AiErrorKind.Auth => "ai_auth",
        AiErrorKind.RateLimited => "ai_rate_limited",
        AiErrorKind.BadRequest => "ai_bad_response",
        _ => "internal",
    };

    public static string UserMessageFor(AiException error) => error.Kind switch
    {
        AiErrorKind.Timeout => "AI 请求超时，请重试",
        AiErrorKind.Auth => "API Key 无效或无权限，请在设置中检查",
        AiErrorKind.RateLimited => "触发限流，请稍后重试",
        AiErrorKind.BadRequest => "AI 拒绝了这次请求",
        AiErrorKind.Network => "连不上 AI 服务，请检查网络",
        AiErrorKind.ServerError => "AI 服务端错误，请稍后重试",
        _ => "AI 调用失败",
    };
}
