using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace QuizSync.App.Pages;

/// <summary>
/// 欢迎页。主按钮指向核心旅程（配对手机）—— 现在它是**真的导航**到配对页，
/// 不再是把结果写进状态条。
/// </summary>
public sealed partial class WelcomePage : Page
{
    public WelcomePage() => InitializeComponent();

    private void OnShowPairCodeClick(object sender, RoutedEventArgs e) =>
        Frame.Navigate(typeof(PairPage));

    /// <summary>
    /// 诊断读数（表数 / 提示词版本）**按需展开**，不常驻首屏状态条（评审：状态条只说用户语言）。
    /// </summary>
    private void OnDiagnosticsClick(object sender, RoutedEventArgs e) =>
        StatusText.Text = $"诊断：{DataLayerReport()} · 识别提示词 {QuizSync.Core.Prompt.ComputePromptVersion()}";

    private static string DataLayerReport()
    {
        try
        {
            using var database = QuizSync.Data.QuizDatabase.CreateFromProtocolSchema(":memory:");
            using var command = database.Connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table'";
            var tables = Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
            return $"数据层就绪（{tables} 张表）";
        }
        catch (Exception error)
        {
            return $"数据层未就绪：{error.Message}";
        }
    }
}
