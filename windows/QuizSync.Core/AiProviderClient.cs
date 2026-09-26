using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace QuizSync.Core;

/// <summary>
/// 真实 provider（三家共用一个发送实现，差异全在 <see cref="AiProviders.BuildRequest"/>）。
///
/// 与 Dart 侧同一口径：**5xx 也走异常翻译**（客户端不抛），失败按
/// <see cref="AiException"/> 分类交给重试策略；网关返回 HTML 错误页时也不能把状态码丢掉。
/// </summary>
public sealed class HttpAiProvider(string providerId, HttpClient? client = null) : IAiProvider
{
    private readonly HttpClient _client = client ?? new HttpClient();

    public string Id => providerId;

    public async Task<AiRawResponse> AnalyzeAsync(
        IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config, CancellationToken cancellationToken = default)
    {
        var request = AiProviders.BuildRequest(providerId, jpegBytesList, prompt, config);

        using var message = new HttpRequestMessage(HttpMethod.Post, request.Url);
        foreach (var (key, value) in request.Headers)
        {
            message.Headers.TryAddWithoutValidation(key, value);
        }

        message.Content = new StringContent(request.Body.ToJsonString(), Encoding.UTF8, "application/json");

        var stopwatch = Stopwatch.StartNew();
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(config.TimeoutSeconds));
            using var response = await _client.SendAsync(message, timeout.Token).ConfigureAwait(false);
            var text = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            stopwatch.Stop();

            if (!response.IsSuccessStatusCode)
            {
                // 状态码优先：即使是 HTML 错误页，也要按 401/429/5xx 分类（否则重试策略会失效）。
                throw AiException.FromStatus((int)response.StatusCode, text);
            }

            // ⚠️ **必须在这里脱壳**（第八轮实测抓到的真 bug）：
            // `IAiProvider` 的契约是「返回模型正文」，而 HTTP 响应是各家的**信封**
            // （OpenAI 兼容 `choices[0].message.content`、Anthropic `content[]`、Gemini `candidates[0]…`）。
            // 原来这里直接返回整个 body，`AnalysisEngine` 又把它交给 `ResponseParser` ——
            // 外层 JSON 能解析成功、但里面没有 `questions`，于是**每次都报「未识别到题目」，
            // 真实回答被静默丢掉**。`AiProviders.ExtractContentText` 早就写好了，
            // 却**只被单测调用过**，生产路径上没有任何人调它。
            // 137 条测试看不见它，是因为 `FakeAiProvider` 返回的已经是脱壳后的正文 ——
            // 假的实现恰好站在了缺失那一步的另一侧。
            return new AiRawResponse(UnwrapOrRaw(text), (int)stopwatch.ElapsedMilliseconds);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AiException(AiErrorKind.Timeout, "请求超时");
        }
        catch (HttpRequestException error)
        {
            throw new AiException(AiErrorKind.Network, $"连接失败: {error.Message}");
        }
    }

    /// <summary>
    /// 各家响应体 → 模型正文。认不出来（不是 JSON / 结构不认识）就**原样返回** ——
    /// 交给上层按「无法解析」处理并保留原文，比在这里编一个空串更容易排查。
    /// </summary>
    private static string UnwrapOrRaw(string text)
    {
        try
        {
            var content = AiProviders.ExtractContentText(JsonNode.Parse(text));
            return content.Length > 0 ? content : text;
        }
        catch (JsonException)
        {
            return text;
        }
    }
}

/// <summary>
/// provider 注册表：id → 实现。不认识的 id 回落到 `openai-compatible`
/// （`ai-contract.md` 第 1 节：它是默认项，也是绝大多数端点的通用形态）。
/// </summary>
public sealed class AiProviderRegistry
{
    private readonly Dictionary<string, Func<IAiProvider>> _factories = new(StringComparer.Ordinal);

    public AiProviderRegistry()
    {
        Register(AiProviders.OpenAiCompatible, () => new HttpAiProvider(AiProviders.OpenAiCompatible));
        Register(AiProviders.Anthropic, () => new HttpAiProvider(AiProviders.Anthropic));
        Register(AiProviders.Gemini, () => new HttpAiProvider(AiProviders.Gemini));
    }

    public IReadOnlyCollection<string> Ids => _factories.Keys;

    public void Register(string providerId, Func<IAiProvider> factory) => _factories[providerId] = factory;

    public IAiProvider Resolve(string providerId) =>
        _factories.TryGetValue(providerId, out var factory)
            ? factory()
            : _factories[AiProviders.OpenAiCompatible]();
}

/// <summary>
/// 固定返回的假 provider：单测与回环测试用（**绝不出网**）。
/// 可以按调用次数依次返回不同结果，用来验证重试与「解析失败再试一次」。
/// </summary>
public sealed class FakeAiProvider(params string[] responses) : IAiProvider
{
    private readonly string[] _responses = responses.Length > 0 ? responses : ["{\"questions\":[]}"];
    private int _calls;

    public string Id => "fake";

    public int CallCount => _calls;

    public List<IReadOnlyList<byte[]>> ReceivedPages { get; } = [];

    public Task<AiRawResponse> AnalyzeAsync(
        IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config, CancellationToken cancellationToken = default)
    {
        ReceivedPages.Add(jpegBytesList);
        var index = Math.Min(_calls, _responses.Length - 1);
        _calls++;
        return Task.FromResult(new AiRawResponse(_responses[index], 1));
    }

    /// <summary>按次数抛异常（验证重试策略）。</summary>
    public static IAiProvider Failing(AiException error, int times)
    {
        var provider = new ThrowingAiProvider(error, times);
        return provider;
    }

    private sealed class ThrowingAiProvider(AiException error, int times) : IAiProvider
    {
        private int _calls;

        public string Id => "throwing";

        public Task<AiRawResponse> AnalyzeAsync(
            IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config, CancellationToken cancellationToken = default)
        {
            _calls++;
            return _calls <= times
                ? Task.FromException<AiRawResponse>(error)
                : Task.FromResult(new AiRawResponse("{\"questions\":[]}", 1));
        }
    }
}
