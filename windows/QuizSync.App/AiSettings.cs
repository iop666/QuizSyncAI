using QuizSync.Core;

namespace QuizSync.App;

/// <summary>
/// AI 配置的来源。**应用内还没有设置页**，所以这一版只读环境变量；
/// 拿不到就明确告诉用户要设哪些变量，绝不假装能识别。
///
/// 变量名与 `QuizSync.Provider.Cli analyze` 保持一致（`QS_AI_*`），
/// 这样命令行验证过的那套配置可以直接喂给界面，不用两处各配一份。
/// </summary>
public static class AiSettings
{
    public const string BaseUrlVariable = "QS_AI_BASE_URL";
    public const string ApiKeyVariable = "QS_AI_API_KEY";
    public const string ModelVariable = "QS_AI_MODEL";
    public const string ProviderVariable = "QS_AI_PROVIDER";

    public static AiConfig Load() => new()
    {
        ProviderId = Environment.GetEnvironmentVariable(ProviderVariable) ?? "openai-compatible",
        BaseUrl = Environment.GetEnvironmentVariable(BaseUrlVariable) ?? string.Empty,
        ApiKey = Environment.GetEnvironmentVariable(ApiKeyVariable) ?? string.Empty,
        Model = Environment.GetEnvironmentVariable(ModelVariable) ?? string.Empty,
    };

    /// <summary>能不能真的调用：Key 与 model 缺一不可（BaseUrl 空则用 provider 默认）。</summary>
    public static bool IsUsable(AiConfig config) =>
        !string.IsNullOrWhiteSpace(config.ApiKey) && !string.IsNullOrWhiteSpace(config.Model);

    /// <summary>没配置时给用户看的话（把变量名写全，别让人猜）。</summary>
    public static string ExplainMissing() =>
        $"还没配置 AI，无法识别。请设置环境变量 {ApiKeyVariable} 与 {ModelVariable}"
        + $"（可选 {BaseUrlVariable}、{ProviderVariable}），然后重启本程序。";
}
