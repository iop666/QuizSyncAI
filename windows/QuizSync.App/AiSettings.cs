using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using QuizSync.Core;

namespace QuizSync.App;

/// <summary>
/// AI 配置的来源：**先看应用设置文件，再看环境变量**。
///
/// 环境变量那条（`QS_AI_*`）保留着，因为它与 `QuizSync.Provider.Cli analyze` 同口径 ——
/// 命令行验证过的那套配置可以直接喂给界面，调试时不用两处各配一份。
///
/// **密钥落盘说明**：`api_key` 存在 `<app>/userdata/ai.json` 里，是**明文**。
/// 与设备令牌（`device.token`）同一处理，迁到 DPAPI 单独一轮做（见 docs/DECISIONS.md）。
/// 界面上必须让用户知道这一点，所以设置页里写明了。
/// </summary>
public static class AiSettings
{
    public const string BaseUrlVariable = "QS_AI_BASE_URL";
    public const string ApiKeyVariable = "QS_AI_API_KEY";
    public const string ModelVariable = "QS_AI_MODEL";
    public const string ProviderVariable = "QS_AI_PROVIDER";

    private const string FileName = "ai.json";

    private static string FilePath => Path.Combine(AppDataDirectory.Ensure(), FileName);

    /// <summary>设置文件里的值（没配置过就是空）。</summary>
    public static AiConfig? LoadSaved()
    {
        if (!File.Exists(FilePath))
        {
            return null;
        }

        try
        {
            var json = JsonNode.Parse(File.ReadAllText(FilePath)) as JsonObject;
            if (json is null)
            {
                return null;
            }

            return new AiConfig
            {
                ProviderId = json["provider_id"]?.ToString() is { Length: > 0 } provider ? provider : "openai-compatible",
                BaseUrl = json["base_url"]?.ToString() ?? string.Empty,
                // 落盘的是密文（`dpapi:` 前缀），这里解回明文；老配置里的明文原样通过。
                ApiKey = SecretStore.Unprotect(json["api_key"]?.ToString() ?? string.Empty),
                Model = json["model"]?.ToString() ?? string.Empty,
            };
        }
        catch (JsonException)
        {
            // 配置文件坏了不该让整个应用起不来：当作没配置，界面上会提示。
            return null;
        }
    }

    /// <summary>存到设置文件（界面「保存」按钮走这里）。</summary>
    public static void Save(AiConfig config)
    {
        var json = new JsonObject
        {
            ["provider_id"] = config.ProviderId,
            ["base_url"] = config.BaseUrl,
            // **加密落盘**（DPAPI, CurrentUser）：挡住「文件被拷到别的机器/账户」这类风险。
            // 注意它挡不住同一用户下运行的程序 —— 别把它当保险箱。
            ["api_key"] = SecretStore.Protect(config.ApiKey),
            ["model"] = config.Model,
            ["timeout_seconds"] = config.TimeoutSeconds,
            ["max_retries"] = config.MaxRetries,
        };

        File.WriteAllText(FilePath, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>
    /// 实际使用的配置：**文件优先，其次环境变量**（文件是用户在界面上显式保存的，更权威）。
    /// </summary>
    public static AiConfig Load()
    {
        var saved = LoadSaved();
        var environment = new AiConfig
        {
            ProviderId = Environment.GetEnvironmentVariable(ProviderVariable) ?? "openai-compatible",
            BaseUrl = Environment.GetEnvironmentVariable(BaseUrlVariable) ?? string.Empty,
            ApiKey = Environment.GetEnvironmentVariable(ApiKeyVariable) ?? string.Empty,
            Model = Environment.GetEnvironmentVariable(ModelVariable) ?? string.Empty,
        };

        if (saved is null)
        {
            return environment;
        }

        return new AiConfig
        {
            ProviderId = Pick(saved.ProviderId, environment.ProviderId),
            BaseUrl = Pick(saved.BaseUrl, environment.BaseUrl),
            ApiKey = Pick(saved.ApiKey, environment.ApiKey),
            Model = Pick(saved.Model, environment.Model),
        };
    }

    private static string Pick(string preferred, string fallback) =>
        string.IsNullOrWhiteSpace(preferred) ? fallback : preferred;

    /// <summary>能不能真的调用：Key 与 model 缺一不可（BaseUrl 空则用 provider 默认）。</summary>
    public static bool IsUsable(AiConfig config) =>
        !string.IsNullOrWhiteSpace(config.ApiKey) && !string.IsNullOrWhiteSpace(config.Model);

    /// <summary>没配置时给用户看的话（指向设置页，而不是只丢一句环境变量）。</summary>
    public static string ExplainMissing() =>
        "还没配置 AI：请到「设置」里填 API Key 与模型（也可以设环境变量 "
        + $"{ApiKeyVariable} / {ModelVariable}），保存后再回来。";
}
