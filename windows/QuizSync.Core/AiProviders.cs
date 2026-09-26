using System.Text.Json.Nodes;

namespace QuizSync.Core;

/// <summary>一次 AI 请求的完整描述（**构造与发送分离**：构造可以离线单测）。</summary>
public sealed record AiHttpRequest(string Url, IReadOnlyDictionary<string, string> Headers, JsonObject Body);

/// <summary>三个真实 provider 的请求构造 + 响应文本抽取（`ai-contract.md` 第 1 节）。</summary>
public static class AiProviders
{
    public const string OpenAiCompatible = "openai-compatible";
    public const string Anthropic = "anthropic";
    public const string Gemini = "gemini";

    public const string OpenAiDefaultBaseUrl = "https://api.openai.com/v1";
    public const string AnthropicDefaultBaseUrl = "https://api.anthropic.com";
    public const string GeminiDefaultBaseUrl = "https://generativelanguage.googleapis.com";

    /// <summary>支持的 provider id（注册表覆盖的这三家）。</summary>
    public static readonly string[] Ids = [OpenAiCompatible, Anthropic, Gemini];

    private static string Base(string configured, string fallback) =>
        string.IsNullOrEmpty(configured) ? fallback : configured;

    /// <summary>
    /// 按 provider 构造请求。多页就是**同一条消息里按顺序放多张图**。
    /// </summary>
    public static AiHttpRequest BuildRequest(
        string providerId, IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config) => providerId switch
    {
        Anthropic => BuildAnthropic(jpegBytesList, prompt, config),
        Gemini => BuildGemini(jpegBytesList, prompt, config),
        _ => BuildOpenAiCompatible(jpegBytesList, prompt, config),
    };

    private static AiHttpRequest BuildOpenAiCompatible(
        IReadOnlyList<byte[]> pages, string prompt, AiConfig config)
    {
        var content = new JsonArray { new JsonObject { ["type"] = "text", ["text"] = prompt } };
        foreach (var page in pages)
        {
            content.Add(new JsonObject
            {
                ["type"] = "image_url",
                ["image_url"] = new JsonObject { ["url"] = $"data:image/jpeg;base64,{Convert.ToBase64String(page)}" },
            });
        }

        var body = new JsonObject
        {
            ["model"] = config.Model,
            ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = content }),
        };

        return new AiHttpRequest(
            $"{Base(config.BaseUrl, OpenAiDefaultBaseUrl)}/chat/completions",
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Authorization"] = $"Bearer {config.ApiKey}",
                ["Content-Type"] = "application/json",
            },
            body);
    }

    private static AiHttpRequest BuildAnthropic(
        IReadOnlyList<byte[]> pages, string prompt, AiConfig config)
    {
        // 注意顺序：Anthropic 的图片块在**前**、文本在后（与 OpenAI 兼容相反）。
        var content = new JsonArray();
        foreach (var page in pages)
        {
            content.Add(new JsonObject
            {
                ["type"] = "image",
                ["source"] = new JsonObject
                {
                    ["type"] = "base64",
                    ["media_type"] = "image/jpeg",
                    ["data"] = Convert.ToBase64String(page),
                },
            });
        }

        content.Add(new JsonObject { ["type"] = "text", ["text"] = prompt });

        var body = new JsonObject
        {
            ["model"] = config.Model,
            ["max_tokens"] = 4096,
            ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = content }),
        };

        return new AiHttpRequest(
            $"{Base(config.BaseUrl, AnthropicDefaultBaseUrl)}/v1/messages",
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["x-api-key"] = config.ApiKey,
                ["anthropic-version"] = "2023-06-01",
                ["Content-Type"] = "application/json",
            },
            body);
    }

    private static AiHttpRequest BuildGemini(
        IReadOnlyList<byte[]> pages, string prompt, AiConfig config)
    {
        var parts = new JsonArray();
        foreach (var page in pages)
        {
            parts.Add(new JsonObject
            {
                ["inline_data"] = new JsonObject
                {
                    ["mime_type"] = "image/jpeg",
                    ["data"] = Convert.ToBase64String(page),
                },
            });
        }

        parts.Add(new JsonObject { ["text"] = prompt });

        var body = new JsonObject
        {
            ["contents"] = new JsonArray(new JsonObject { ["parts"] = parts }),
        };

        return new AiHttpRequest(
            $"{Base(config.BaseUrl, GeminiDefaultBaseUrl)}/v1beta/models/{config.Model}:generateContent?key={config.ApiKey}",
            new Dictionary<string, string>(StringComparer.Ordinal) { ["Content-Type"] = "application/json" },
            body);
    }

    /// <summary>
    /// 从各家响应体里抽出文本：OpenAI 兼容 `choices[0].message.content`（字符串或内容块数组）、
    /// Anthropic `content[]` 里 `type=text` 的块、Gemini `candidates[0].content.parts[]`。
    /// 认不出来就返回空串（由上层按「解析失败」处理）。
    /// </summary>
    public static string ExtractContentText(JsonNode? raw)
    {
        if (raw is not JsonObject data)
        {
            return string.Empty;
        }

        // OpenAI 兼容。
        if (data["choices"] is JsonArray { Count: > 0 } choices && choices[0] is JsonObject first)
        {
            if (first["message"] is JsonObject message)
            {
                switch (message["content"])
                {
                    case JsonValue value when value.TryGetValue<string>(out var text):
                        return text;
                    case JsonArray parts:
                        return string.Concat(parts.OfType<JsonObject>().Select(p => p["text"]?.ToString() ?? string.Empty));
                }
            }
        }

        // Anthropic。
        if (data["content"] is JsonArray blocks)
        {
            var text = string.Concat(blocks.OfType<JsonObject>()
                .Where(b => b["type"]?.ToString() == "text")
                .Select(b => b["text"]?.ToString() ?? string.Empty));
            if (text.Length > 0)
            {
                return text;
            }
        }

        // Gemini。
        if (data["candidates"] is JsonArray { Count: > 0 } candidates && candidates[0] is JsonObject candidate &&
            candidate["content"] is JsonObject candidateContent && candidateContent["parts"] is JsonArray geminiParts)
        {
            return string.Concat(geminiParts.OfType<JsonObject>().Select(p => p["text"]?.ToString() ?? string.Empty));
        }

        return string.Empty;
    }
}
