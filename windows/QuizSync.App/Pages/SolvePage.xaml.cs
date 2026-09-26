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

    protected override void OnNavigatedTo(NavigationEventArgs e)
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

    private async void OnCaptureClick(object sender, RoutedEventArgs e)
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
                    deviceId: "windows-local");
                return await engine.AnalyzeImageAsync(shot.Jpeg, shot.ImageHash, config).ConfigureAwait(false);
            }).ConfigureAwait(true);

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
