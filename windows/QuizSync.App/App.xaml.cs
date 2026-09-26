using Microsoft.UI.Xaml;

namespace QuizSync.App;

/// <summary>Phase 6 外壳的入口。这一版只做一件事：**证明 WinUI 3 在本机能编能跑**。</summary>
public partial class App : Application
{
    private Window? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
