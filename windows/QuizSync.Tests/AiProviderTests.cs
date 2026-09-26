using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using QuizSync.Core;
using Xunit;

namespace QuizSync.Tests;

/// <summary>假的 HTTP 处理器：不出网，按脚本返回状态码与响应体。</summary>
internal sealed class ScriptedHandler(Func<HttpRequestMessage, (HttpStatusCode Status, string Body)> script) : HttpMessageHandler
{
    public List<HttpRequestMessage> Requests { get; } = [];

    public List<string> Bodies { get; } = [];

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        Bodies.Add(request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken));
        var (status, body) = script(request);
        return new HttpResponseMessage(status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
    }
}

/// <summary>
/// 三个 provider 的请求构造与响应抽取（`ai-contract.md` 第 1 节），
/// 与 Dart 侧 `test/ai/providers_test.dart` 同一套期望。
/// </summary>
public sealed class AiProviderTests
{
    private static readonly byte[] Page1 = [0xFF, 0xD8, 0x01];
    private static readonly byte[] Page2 = [0xFF, 0xD8, 0x02];

    private static AiConfig Config(string providerId, string baseUrl = "", string apiKey = "k", string model = "m") =>
        new() { ProviderId = providerId, BaseUrl = baseUrl, ApiKey = apiKey, Model = model };

    [Fact]
    public void OpenAi_compatible_request_shape()
    {
        var request = AiProviders.BuildRequest(
            AiProviders.OpenAiCompatible, [Page1, Page2], "PROMPT", Config(AiProviders.OpenAiCompatible));

        Assert.Equal("https://api.openai.com/v1/chat/completions", request.Url);
        Assert.Equal("Bearer k", request.Headers["Authorization"]);
        Assert.Equal("m", request.Body["model"]!.GetValue<string>());

        var content = request.Body["messages"]![0]!["content"]!.AsArray();
        Assert.Equal(3, content.Count); // 文本 + 两页图
        Assert.Equal("text", content[0]!["type"]!.GetValue<string>());
        Assert.Equal("PROMPT", content[0]!["text"]!.GetValue<string>());
        Assert.Equal("image_url", content[1]!["type"]!.GetValue<string>());
        var dataUrl = content[1]!["image_url"]!["url"]!.GetValue<string>();
        Assert.StartsWith("data:image/jpeg;base64,", dataUrl, StringComparison.Ordinal);
        Assert.Equal(Convert.ToBase64String(Page1), dataUrl["data:image/jpeg;base64,".Length..]);
        Assert.Equal(Convert.ToBase64String(Page2), content[2]!["image_url"]!["url"]!.GetValue<string>()["data:image/jpeg;base64,".Length..]);
    }

    [Fact]
    public void Anthropic_request_puts_images_first_and_uses_its_own_headers()
    {
        var request = AiProviders.BuildRequest(
            AiProviders.Anthropic, [Page1, Page2], "PROMPT", Config(AiProviders.Anthropic));

        Assert.Equal("https://api.anthropic.com/v1/messages", request.Url);
        Assert.Equal("k", request.Headers["x-api-key"]);
        Assert.Equal("2023-06-01", request.Headers["anthropic-version"]);
        Assert.Equal(4096, request.Body["max_tokens"]!.GetValue<int>());

        var content = request.Body["messages"]![0]!["content"]!.AsArray();
        Assert.Equal(3, content.Count);
        // Anthropic：图片在前、文本在后。
        Assert.Equal("image", content[0]!["type"]!.GetValue<string>());
        Assert.Equal("base64", content[0]!["source"]!["type"]!.GetValue<string>());
        Assert.Equal("image/jpeg", content[0]!["source"]!["media_type"]!.GetValue<string>());
        Assert.Equal("text", content[2]!["type"]!.GetValue<string>());
    }

    [Fact]
    public void Gemini_request_uses_inline_data_and_key_in_query()
    {
        var request = AiProviders.BuildRequest(
            AiProviders.Gemini, [Page1], "PROMPT", Config(AiProviders.Gemini, apiKey: "KEY", model: "gemini-2.0"));

        Assert.Equal(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0:generateContent?key=KEY",
            request.Url);
        var parts = request.Body["contents"]![0]!["parts"]!.AsArray();
        Assert.Equal(2, parts.Count);
        Assert.Equal("image/jpeg", parts[0]!["inline_data"]!["mime_type"]!.GetValue<string>());
        Assert.Equal(Convert.ToBase64String(Page1), parts[0]!["inline_data"]!["data"]!.GetValue<string>());
        Assert.Equal("PROMPT", parts[1]!["text"]!.GetValue<string>());
    }

    [Fact]
    public void Custom_base_url_wins_over_the_default()
    {
        var request = AiProviders.BuildRequest(
            AiProviders.OpenAiCompatible, [Page1], "P", Config(AiProviders.OpenAiCompatible, baseUrl: "https://my.gateway/v1"));
        Assert.Equal("https://my.gateway/v1/chat/completions", request.Url);
    }

    [Theory]
    [InlineData("""{"choices":[{"message":{"content":"答案"}}]}""", "答案")]
    [InlineData("""{"choices":[{"message":{"content":[{"type":"text","text":"A"},{"type":"text","text":"B"}]}}]}""", "AB")]
    [InlineData("""{"content":[{"type":"text","text":"安"},{"type":"tool_use","text":"忽略"},{"type":"text","text":"全"}]}""", "安全")]
    [InlineData("""{"candidates":[{"content":{"parts":[{"text":"G"},{"text":"1"}]}}]}""", "G1")]
    [InlineData("""{"unexpected":true}""", "")]
    [InlineData("not json at all", "")]
    public void Content_text_extraction_handles_all_three_shapes(string body, string expected)
    {
        var parsed = TryParse(body);
        Assert.Equal(expected, AiProviders.ExtractContentText(parsed));
    }

    [Fact]
    public void Registry_covers_all_three_providers_and_falls_back()
    {
        var registry = new AiProviderRegistry();
        Assert.Equal(["anthropic", "gemini", "openai-compatible"], registry.Ids.OrderBy(x => x, StringComparer.Ordinal));
        Assert.Equal("openai-compatible", registry.Resolve("openai-compatible").Id);
        Assert.Equal("anthropic", registry.Resolve("anthropic").Id);
        Assert.Equal("gemini", registry.Resolve("gemini").Id);
        // 不认识的 id → 回落到默认形态。
        Assert.Equal("openai-compatible", registry.Resolve("some-new-vendor").Id);
    }

    [Fact]
    public async Task Successful_call_returns_text_and_latency()
    {
        var handler = new ScriptedHandler(_ => (HttpStatusCode.OK, """{"choices":[{"message":{"content":"好的"}}]}"""));
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));

        var response = await provider.AnalyzeOneAsync(Page1, "P", Config(AiProviders.OpenAiCompatible));

        // ⚠️ 必须是**相等**，不能是 `Assert.Contains`（第八轮教训）：
        // 整个信封 `{"choices":[{"message":{"content":"好的"}}]}` 里也包含「好的」，
        // 于是「有没有脱壳」这件事在子串断言下**完全看不出来** —— 真 bug 就是这么藏了 137 条测试。
        Assert.Equal("好的", response.Text);
        Assert.True(response.LatencyMs >= 0);
        Assert.Single(handler.Requests);
        Assert.Equal("Bearer k", handler.Requests[0].Headers.GetValues("Authorization").Single());
    }

    /// <summary>
    /// 三家响应体都要能脱壳成**模型正文**（`IAiProvider` 的契约是返回正文，不是 HTTP 信封）。
    /// 生产路径漏了这一步的后果是：外层 JSON 解析成功、里面没有 `questions`，
    /// 于是每次都报「未识别到题目」，真实回答被静默丢掉。
    /// </summary>
    [Theory]
    [InlineData("""{"choices":[{"message":{"content":"正文A"}}]}""", "正文A")]
    [InlineData("""{"choices":[{"message":{"content":[{"type":"text","text":"正文"},{"type":"text","text":"B"}]}}]}""", "正文B")]
    [InlineData("""{"content":[{"type":"text","text":"正文C"}]}""", "正文C")]
    [InlineData("""{"candidates":[{"content":{"parts":[{"text":"正文D"}]}}]}""", "正文D")]
    public async Task Provider_returns_unwrapped_content_not_the_raw_envelope(string body, string expected)
    {
        var handler = new ScriptedHandler(_ => (HttpStatusCode.OK, body));
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));

        var response = await provider.AnalyzeOneAsync(Page1, "P", Config(AiProviders.OpenAiCompatible));

        Assert.Equal(expected, response.Text);
    }

    /// <summary>认不出来的响应体要**原样**返回（交给上层按「无法解析」处理并保留原文）。</summary>
    [Fact]
    public async Task Unrecognised_body_is_returned_verbatim()
    {
        var handler = new ScriptedHandler(_ => (HttpStatusCode.OK, "这不是 JSON"));
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));

        var response = await provider.AnalyzeOneAsync(Page1, "P", Config(AiProviders.OpenAiCompatible));

        Assert.Equal("这不是 JSON", response.Text);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, AiErrorKind.Auth)]
    [InlineData(HttpStatusCode.Forbidden, AiErrorKind.Auth)]
    [InlineData(HttpStatusCode.TooManyRequests, AiErrorKind.RateLimited)]
    [InlineData(HttpStatusCode.BadRequest, AiErrorKind.BadRequest)]
    [InlineData(HttpStatusCode.InternalServerError, AiErrorKind.ServerError)]
    [InlineData(HttpStatusCode.BadGateway, AiErrorKind.ServerError)]
    public async Task Http_failures_map_to_retry_kinds_even_with_html_bodies(HttpStatusCode status, AiErrorKind expected)
    {
        // 502/504 常常是网关吐的 HTML：必须看状态码，不能因为 body 不是 JSON 就归成 unknown。
        var handler = new ScriptedHandler(_ => (status, "<html>gateway error</html>"));
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));

        var error = await Assert.ThrowsAsync<AiException>(
            () => provider.AnalyzeOneAsync(Page1, "P", Config(AiProviders.OpenAiCompatible)));

        Assert.Equal(expected, error.Kind);
        Assert.Equal((int)status, error.StatusCode);
    }

    [Fact]
    public async Task Timeout_becomes_a_retryable_timeout_exception()
    {
        var handler = new SlowHandler();
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));
        var config = Config(AiProviders.OpenAiCompatible) with { TimeoutSeconds = 1 };

        var error = await Assert.ThrowsAsync<AiException>(() => provider.AnalyzeOneAsync(Page1, "P", config));

        Assert.Equal(AiErrorKind.Timeout, error.Kind);
        Assert.True(error.Retryable);
    }

    private sealed class SlowHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK);
        }
    }

    [Fact]
    public async Task Connection_failure_becomes_a_retryable_network_exception()
    {
        var handler = new ScriptedHandler(_ => throw new HttpRequestException("connection refused"));
        var provider = new HttpAiProvider(AiProviders.OpenAiCompatible, new HttpClient(handler));

        var error = await Assert.ThrowsAsync<AiException>(
            () => provider.AnalyzeOneAsync(Page1, "P", Config(AiProviders.OpenAiCompatible)));

        Assert.Equal(AiErrorKind.Network, error.Kind);
        Assert.True(error.Retryable);
    }

    private static JsonNode? TryParse(string text)
    {
        try
        {
            return JsonNode.Parse(text);
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}
