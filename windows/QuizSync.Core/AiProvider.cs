using System.Text.Json.Nodes;

namespace QuizSync.Core;

/// <summary>AI 调用配置（`ai-contract.md` 第 1 节）。</summary>
public sealed record AiConfig
{
    /// <summary>`openai-compatible` | `anthropic` | `gemini`。</summary>
    public string ProviderId { get; init; } = "openai-compatible";

    /// <summary>可空，空则用 provider 默认。</summary>
    public string BaseUrl { get; init; } = string.Empty;

    public string ApiKey { get; init; } = string.Empty;

    public string Model { get; init; } = string.Empty;

    public int TimeoutSeconds { get; init; } = 90;

    public int MaxRetries { get; init; } = 2;

    /// <summary>
    /// 落盘的形态：**`api_key` 绝不出现**（不进 JSON / 日志 / 数据库）。
    /// </summary>
    public JsonObject ToSecureJson() => new()
    {
        ["provider_id"] = ProviderId,
        ["base_url"] = BaseUrl,
        ["model"] = Model,
        ["timeout_seconds"] = TimeoutSeconds,
        ["max_retries"] = MaxRetries,
    };
}

/// <summary>provider 的原始返回（只负责「发请求取文本」，JSON 解析在 ResponseParser）。</summary>
public sealed record AiRawResponse(string Text, int LatencyMs);

/// <summary>AI 调用异常分类（重试策略的依据，`ai-contract.md` 第 4 节）。</summary>
public enum AiErrorKind
{
    /// <summary>超时（可重试）。</summary>
    Timeout,

    /// <summary>连接失败（可重试）。</summary>
    Network,

    /// <summary>HTTP 5xx（可重试）。</summary>
    ServerError,

    /// <summary>HTTP 429（可重试）。</summary>
    RateLimited,

    /// <summary>HTTP 400：请求格式错（不可重试）。</summary>
    BadRequest,

    /// <summary>HTTP 401 / 403：Key 无效或无权限（不可重试）。</summary>
    Auth,

    /// <summary>其他未知错误。</summary>
    Unknown,
}

public sealed class AiException(AiErrorKind kind, string message, int? statusCode = null) : Exception(message)
{
    public AiErrorKind Kind { get; } = kind;

    public int? StatusCode { get; } = statusCode;

    /// <summary>可重试的只有这四类：超时、连接失败、5xx、429。</summary>
    public bool Retryable => Kind is AiErrorKind.Timeout or AiErrorKind.Network
        or AiErrorKind.ServerError or AiErrorKind.RateLimited;

    /// <summary>把 HTTP 状态码映射成异常分类（与 Dart 侧一致）。</summary>
    public static AiException FromStatus(int statusCode, string message) => statusCode switch
    {
        400 => new AiException(AiErrorKind.BadRequest, message, statusCode),
        401 or 403 => new AiException(AiErrorKind.Auth, message, statusCode),
        429 => new AiException(AiErrorKind.RateLimited, message, statusCode),
        >= 500 => new AiException(AiErrorKind.ServerError, message, statusCode),
        _ => new AiException(AiErrorKind.Unknown, message, statusCode),
    };

    public override string ToString() => $"AiException({Kind} {StatusCode}: {Message})";
}

/// <summary>
/// Provider 抽象（`ai-contract.md` 第 1 节）。实现必须可替换成假实现供单测使用。
/// 入口是**列表**：一次识别可以是多页图片（单图调用方传长度为 1 的列表）。
/// </summary>
public interface IAiProvider
{
    string Id { get; }

    Task<AiRawResponse> AnalyzeAsync(IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config, CancellationToken cancellationToken = default);
}

public static class AiProviderExtensions
{
    /// <summary>单图便捷调用（内部走多图通道）。</summary>
    public static Task<AiRawResponse> AnalyzeOneAsync(
        this IAiProvider provider, byte[] jpegBytes, string prompt, AiConfig config, CancellationToken cancellationToken = default) =>
        provider.AnalyzeAsync([jpegBytes], prompt, config, cancellationToken);
}
