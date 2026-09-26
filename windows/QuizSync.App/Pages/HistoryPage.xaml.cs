using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using QuizSync.Data;

namespace QuizSync.App.Pages;

/// <summary>
/// 历史页：列出本地库里的会话，点一条看当时的题目。
///
/// 刻意**不用 DataTemplate + 绑定**：这里的行是代码里拼的，少一层绑定就少一类
/// 「模板里绑错属性、界面上一片空白但编译通过」的坑（列表项本来也就两个字段）。
/// </summary>
public sealed partial class HistoryPage : Page
{
    public HistoryPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Render();
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e) => Render();

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

    private void Render()
    {
        BodyPanel.Children.Clear();

        try
        {
            using var database = QuizDatabase.OpenOrCreate(AppDataDirectory.DatabasePath());
            var sessions = SessionRecorder.RecentSessions(database);

            if (sessions.Count == 0)
            {
                AddText("还没有记录。去「截屏搜题」识别一次，结果就会出现在这里。", secondary: true);
                StatusText.Text = "本地还没有识别记录";
                return;
            }

            AddText($"共 {sessions.Count} 条记录（显示最近 50 条）", secondary: true);
            foreach (var session in sessions)
            {
                var button = new Button
                {
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Left,
                    Content = DescribeSession(session),
                };
                button.Click += (_, _) => ShowSession(session);
                BodyPanel.Children.Add(button);
            }

            StatusText.Text = $"已加载 {sessions.Count} 条记录";
        }
        catch (Exception error)
        {
            AddText($"读取本地记录失败：{error.Message}", secondary: false);
            StatusText.Text = "读取失败";
        }
    }

    private void ShowSession(RecordedSession session)
    {
        // 详情就地展开在列表下面（这一版不做二级页）。
        Render();
        AddText($"—— {DescribeSession(session)} ——", secondary: false);

        try
        {
            using var database = QuizDatabase.OpenOrCreate(AppDataDirectory.DatabasePath());
            var questions = SessionRecorder.QuestionsOf(database, session.SessionId);
            if (questions.Count == 0)
            {
                AddText("这条会话里没有保存题目。", secondary: true);
                return;
            }

            foreach (var question in questions)
            {
                var number = string.IsNullOrWhiteSpace(question.QuestionNo)
                    ? (question.Ordinal + 1).ToString(System.Globalization.CultureInfo.InvariantCulture)
                    : question.QuestionNo!;
                AddText($"{number}. {question.Stem}", secondary: false);

                var answer = !string.IsNullOrWhiteSpace(question.AnswerText)
                    ? question.AnswerText!
                    : string.Join(" ", question.Choice ?? []);
                AddText($"答案：{(string.IsNullOrWhiteSpace(answer) ? "（AI 未给出）" : answer)}", secondary: true);
            }

            StatusText.Text = $"这条会话有 {questions.Count} 道题";
        }
        catch (Exception error)
        {
            AddText($"读取题目失败：{error.Message}", secondary: false);
        }
    }

    private static string DescribeSession(RecordedSession session)
    {
        var when = DateTimeOffset.FromUnixTimeMilliseconds(session.CreatedAt).ToLocalTime();
        var model = string.IsNullOrWhiteSpace(session.AiModel) ? "未知模型" : session.AiModel!;
        return $"{when:MM-dd HH:mm} · {session.QuestionCount} 道题 · {model}"
             + (session.Cached ? " · 缓存" : string.Empty)
             + (session.SourceDevice == "windows-local" ? string.Empty : $" · 来自 {session.SourceDevice}");
    }

    private void AddText(string text, bool secondary)
    {
        BodyPanel.Children.Add(new TextBlock
        {
            Text = text,
            TextWrapping = TextWrapping.Wrap,
            Style = Application.Current.Resources[secondary ? "QsSecondaryTextStyle" : "QsBodyTextStyle"] as Style,
        });
    }
}
