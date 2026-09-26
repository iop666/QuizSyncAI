using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Navigation;
using QuizSync.Core;
using QuizSync.Data;
using QuizSync.Provider;

namespace QuizSync.App.Pages;

/// <summary>
/// 截屏搜题页。与 `QuizSync.Provider.Cli analyze` **走同一套内核**
/// （`ScreenJpeg` → `AnalysisEngine` → `ResponseParser`），只是把结果画到界面上。
///
/// 界面上要如实显示三类状态，不糊弄：
/// * AI 没配置 → 把该设的环境变量写清楚（应用内还没有设置页）；
/// * 截图失败 → 明说；
/// * 识别失败 → 显示错误码与文案（含「未识别到题目」这种正常的空结果）。
/// </summary>
public sealed partial class SolvePage : Page
{
    public SolvePage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var config = AiSettings.Load();
        if (!AiSettings.IsUsable(config))
        {
            StatusText.Text = AiSettings.ExplainMissing();
            CaptureButton.IsEnabled = false;
            return;
        }

        StatusText.Text = $"AI 就绪：{config.ProviderId}"
                        + (string.IsNullOrWhiteSpace(config.Model) ? string.Empty : $" · {config.Model}");

        // 由全局热键进来的（参数 true）：直接开跑，用户按 F8 就是想立刻识别。
        if (e.Parameter is true && AiSettings.IsUsable(config))
        {
            await RunCaptureAsync();
        }
    }

    private void OnBackClick(object sender, RoutedEventArgs e)
    {
        if (Frame.CanGoBack)
        {
            Frame.GoBack();
        }
        else
        {
            Frame.Navigate(typeof(WelcomePage));
        }
    }

    /// <summary>按钮与**全局热键**走同一条流程（热键从 Host 页/别的窗口按下时也要能跑）。</summary>
    private async void OnCaptureClick(object sender, RoutedEventArgs e) => await RunCaptureAsync();

    /// <summary>
    /// 截屏 → 识别 → 落库 → 推主机。界面上要如实显示三类状态，不糊弄：
    /// AI 没配置（把该设的写清楚）、截图失败、识别失败（含「未识别到题目」这种正常的空结果）。
    /// </summary>
    private async Task RunCaptureAsync()
    {
        var config = AiSettings.Load();
        if (!AiSettings.IsUsable(config))
        {
            StatusText.Text = AiSettings.ExplainMissing();
            return;
        }

        CaptureButton.IsEnabled = false;
        ResultsPanel.Children.Clear();
        StatusText.Text = "正在截屏…";

        try
        {
            // 截屏要藏自己的窗口，必须在 UI 线程上做同步调用；耗时的是后面的网络往返。
            var shot = ScreenJpeg.Capture(AppWindowScope.Title);
            if (shot is null)
            {
                StatusText.Text = "截屏失败：拿不到屏幕尺寸。";
                return;
            }

            ShowNotice($"已截屏 {shot.SourceWidth}×{shot.SourceHeight} → {shot.Width}×{shot.Height}"
                       + $"，JPEG {shot.Jpeg.Length / 1024} KB", secondary: true);
            StatusText.Text = "正在识别…";

            string? pushNotice = null;
            var outcome = await Task.Run(async () =>
            {
                // 本地库用**应用自己的**目录：服务端那个库是另一套结构（没有 analysis_cache），
                // 指过去会报 no such column: prompt_version。服务端目录只用来读 control.token。
                using var database = QuizDatabase.OpenOrCreate(AppDataDirectory.DatabasePath());
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(config.TimeoutSeconds + 30) };
                var engine = new AnalysisEngine(
                    new HttpAiProvider(config.ProviderId, http),
                    new AnalysisCache(database),
                    new QuotaGuard(database),
                    deviceId: SyncUploader.DeviceId);
                var result = await engine.AnalyzeImageAsync(shot.Jpeg, shot.ImageHash, config).ConfigureAwait(false);

                // 识别成功就落库（走 LocalStore → 生成同步 op），然后**推给主机** ——
                // 不推的话手机端永远拉不到（第十一轮只能用脚本给服务端播种才验到 Android 拉取）。
                if (result.Ok)
                {
                    var store = new LocalStore(database, SyncUploader.DeviceId);
                    SessionRecorder.Record(
                        store,
                        shot.ImageHash,
                        SyncUploader.DeviceId,
                        [.. result.Questions.Select(Map)],
                        now: DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        aiProvider: config.ProviderId,
                        aiModel: config.Model,
                        latencyMs: result.LatencyMs,
                        cached: result.FromCache);
                    pushNotice = await TryPushAsync(database).ConfigureAwait(false);
                }

                return result;
            }).ConfigureAwait(true);

            if (!string.IsNullOrWhiteSpace(pushNotice))
            {
                ShowNotice(pushNotice!, secondary: true);
            }

            Render(outcome);
        }
        catch (Exception error)
        {
            StatusText.Text = $"识别失败：{error.Message}";
        }
        finally
        {
            CaptureButton.IsEnabled = true;
        }
    }

    /// <summary>
    /// 推送到主机。**任何失败都只返回一句话、不抛** —— 本地记录已经落库了，
    /// 推不上去不该让这次识别看起来失败（网络/主机状态是暂时性的）。
    /// </summary>
    private static async Task<string?> TryPushAsync(QuizDatabase database)
    {
        try
        {
            var probe = await new QuizSync.ServerBridge.HostDiscovery().ProbeAsync().ConfigureAwait(false);
            if (probe is null)
            {
                return "主机未启动：改动只留在本机（启动 QuizSync.Server.Cli run 后再点一次即可同步）";
            }

            var directory = HostDataDirectory.Find();
            var controlToken = directory is null ? null : QuizSync.ServerBridge.HostControl.FindControlToken(directory);
            if (controlToken is null)
            {
                return "读不到控制令牌：改动只留在本机";
            }

            return await SyncUploader.PushPendingAsync(database, probe.BaseUrl, controlToken).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            return $"推送失败（改动仍在本机）：{error.Message}";
        }
    }

    /// <summary>
    /// `Question` → 落库用的字段。**题型走 `QuestionTypes.Wire`**（协议值是
    /// `single`/`multi`/`judge`/`blank`/`subjective`），不要自己拼字符串 ——
    /// 手写 `single_choice` 之类在库里能存下，但对方端 `IsKnown` 不认。
    /// </summary>
    private static RecordedQuestion Map(Question question) => new(
        Ordinal: question.Ordinal,
        Stem: question.Stem,
        Type: question.Type.Wire(),
        QuestionNo: question.QuestionNo,
        AnswerText: question.AnswerText,
        Analysis: question.Analysis,
        Choice: question.Choice,
        Confidence: question.Confidence,
        NeedReview: question.NeedReview);

    private void Render(AnalysisOutcome outcome)
    {
        if (!outcome.Ok)
        {
            var code = outcome.ErrorCode ?? "unknown";
            var message = outcome.ErrorMessage ?? "没有可用结果";
            ShowNotice($"识别没成功（{code}）：{message}", secondary: false);
            if (!string.IsNullOrWhiteSpace(outcome.RawText))
            {
                ShowNotice("AI 原文：" + Truncate(outcome.RawText!, 400), secondary: true);
            }

            StatusText.Text = outcome.FromCache ? "来自缓存，但没有题目" : $"识别结束：{code}";
            return;
        }

        foreach (var question in outcome.Questions)
        {
            var lines = new List<string>();
            if (!string.IsNullOrWhiteSpace(question.QuestionNo))
            {
                lines.Add(question.QuestionNo!);
            }

            var header = lines.Count > 0 ? $"{lines[0]}. " : string.Empty;
            ShowNotice(header + question.Stem, secondary: false);

            var answer = !string.IsNullOrWhiteSpace(question.AnswerText)
                ? question.AnswerText!
                : string.Join(" ", question.Choice);
            ShowNotice($"答案：{(string.IsNullOrWhiteSpace(answer) ? "（AI 未给出）" : answer)}", secondary: true);

            if (!string.IsNullOrWhiteSpace(question.Analysis))
            {
                ShowNotice(Truncate(question.Analysis, 300), secondary: true);
            }
        }

        StatusText.Text = $"识别完成：{outcome.Questions.Count} 道题"
                        + (outcome.FromCache ? "（来自缓存）" : $"，{outcome.LatencyMs} ms")
                        + (outcome.ProviderCalls > 1 ? $"，{outcome.ProviderCalls} 次调用" : string.Empty);
    }

    private void ShowNotice(string text, bool secondary)
    {
        var block = new TextBlock
        {
            Text = text,
            TextWrapping = TextWrapping.Wrap,
            Style = Application.Current.Resources[secondary ? "QsSecondaryTextStyle" : "QsBodyTextStyle"] as Style,
        };
        ResultsPanel.Children.Add(block);
    }

    private static string Truncate(string text, int max) =>
        text.Length <= max ? text : text[..max] + "…";
}
