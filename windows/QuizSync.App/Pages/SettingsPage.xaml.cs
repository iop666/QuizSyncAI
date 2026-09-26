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
