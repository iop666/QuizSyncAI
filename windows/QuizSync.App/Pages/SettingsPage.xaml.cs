using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using QuizSync.Core;

namespace QuizSync.App.Pages;

/// <summary>
/// 设置页（第一版）：只做 AI 配置。
///
/// 之前应用**只能靠环境变量**配置 AI —— 用户装了程序也填不了 Key，
/// 等于只能靠桩跑（第十九轮之前的验证全是我在命令行设 `QS_AI_*`）。
/// 这一页把那条路补上：文件优先、环境变量兜底，与 `Provider.Cli analyze` 同口径。
/// </summary>
public sealed partial class SettingsPage : Page
{
    public SettingsPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        // 回显「实际生效」的值（文件优先、环境变量兜底），用户一眼能看到现在用的是什么。
        var effective = AiSettings.Load();
        ProviderBox.Text = effective.ProviderId;
        BaseUrlBox.Text = effective.BaseUrl;
        ApiKeyBox.Password = effective.ApiKey;
        ModelBox.Text = effective.Model;

        var ball = BallSettings.Load();
        BallEnabledSwitch.IsOn = ball.Enabled;
        BallSizeSlider.Value = ball.Diameter;
        BallOpacitySlider.Value = ball.Opacity;

        StatusText.Text = AiSettings.IsUsable(effective)
            ? $"当前已可用：{effective.ProviderId}"
              + (string.IsNullOrWhiteSpace(effective.Model) ? string.Empty : $" · {effective.Model}")
            : "当前还没配好（缺 API Key 或模型）—— 填好点保存即可。";
    }

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var config = new AiConfig
            {
                ProviderId = string.IsNullOrWhiteSpace(ProviderBox.Text) ? "openai-compatible" : ProviderBox.Text.Trim(),
                BaseUrl = BaseUrlBox.Text.Trim(),
                ApiKey = ApiKeyBox.Password.Trim(),
                Model = ModelBox.Text.Trim(),
            };

            AiSettings.Save(config);
            StatusText.Text = AiSettings.IsUsable(config)
                ? "已保存，可以去「截屏搜题」了。"
                : "已保存，但还缺 API Key 或模型 —— 现在还不能识别。";
        }
        catch (Exception error)
        {
            StatusText.Text = $"保存失败：{error.Message}";
        }
    }

    /// <summary>
    /// 「查看配对码与设备」：复用配对页那条链路（控制面读配对码）。
    /// 主机没启动 / 读不到控制令牌时**如实说明找过哪些目录**，不假装查过。
    /// </summary>
    private async void OnRefreshHostClick(object sender, RoutedEventArgs e)
    {
        RefreshHostButton.IsEnabled = false;
        HostText.Text = "正在查找本机服务端…";
        try
        {
            var probe = await new QuizSync.ServerBridge.HostDiscovery().ProbeAsync().ConfigureAwait(true);
            if (probe is null)
            {
                HostText.Text = "本机服务端未启动。请先运行 QuizSync.Server.Cli run，再点一次。";
                return;
            }

            var directory = HostDataDirectory.Find();
            var controlToken = directory is null ? null : QuizSync.ServerBridge.HostControl.FindControlToken(directory);
            if (controlToken is null)
            {
                HostText.Text = HostDataDirectory.ExplainMissing();
                return;
            }

            var code = await new QuizSync.ServerBridge.HostControl(probe.BaseUrl, controlToken)
                .PairCodeAsync().ConfigureAwait(true);
            var pairCode = code?["code"]?.ToString() ?? "（没读到）";
            var port = code?["port"]?.ToString() ?? "?";

            // 设备列表要的是**设备令牌**（Bearer），控制令牌不是 —— 用错了会 401。
            // 设备令牌是应用自己与主机配对时拿到的（`SyncUploader` 存在 userdata/device.token）。
            var deviceTokenPath = System.IO.Path.Combine(AppDataDirectory.Ensure(), "device.token");
            var deviceToken = System.IO.File.Exists(deviceTokenPath)
                ? System.IO.File.ReadAllText(deviceTokenPath).Trim()
                : null;

            if (string.IsNullOrEmpty(deviceToken))
            {
                HostText.Text = $"配对码 {pairCode}（端口 {port}）；还没拿到设备令牌，"
                              + "先去「截屏搜题」识别一次（那一步会自动与主机配对）。";
                return;
            }

            var client = new QuizSync.ServerBridge.HostClient(probe.BaseUrl);
            client.UseToken(deviceToken);
            var devices = await client.DevicesAsync().ConfigureAwait(true);
            var names = devices?["devices"] is System.Text.Json.Nodes.JsonArray list
                ? string.Join("、", list.OfType<System.Text.Json.Nodes.JsonObject>()
                    .Select(d => $"{d["name"]}（{d["platform"]}）"))
                : string.Empty;

            HostText.Text = $"配对码 {pairCode}（端口 {port}）"
                          + (string.IsNullOrEmpty(names) ? "；还没有已配对设备" : $"；已配对：{names}");
        }
        catch (Exception error)
        {
            HostText.Text = $"查询失败：{error.Message}";
        }
        finally
        {
            RefreshHostButton.IsEnabled = true;
        }
    }

    /// <summary>
    /// 应用悬浮球设置：存盘 + **立刻重建球**（`App.ApplyBallSettings`）。
    ///
    /// 「改了要立刻见效」是 1.1.0 用户明确反馈过的要求（当年四项设置全都调不动），
    /// 所以这里不留「重启后生效」这种含糊说法 —— 存完立刻重建，状态条也如实写出来。
    /// </summary>
    private void OnApplyBallClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var ball = BallSettings.Load();
            ball.Enabled = BallEnabledSwitch.IsOn;
            ball.Diameter = (int)Math.Round(BallSizeSlider.Value);
            ball.Opacity = (int)Math.Round(BallOpacitySlider.Value);
            ball.Save();

            (Application.Current as App)?.ApplyBallSettings();

            StatusText.Text = ball.Enabled
                ? $"悬浮球已应用：{ball.Diameter} 像素 · 不透明度 {ball.Opacity}%"
                : "悬浮球已关闭（窗口已移除）。";
        }
        catch (Exception error)
        {
            StatusText.Text = $"应用悬浮球设置失败：{error.Message}";
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
}
