using System;
using Microsoft.UI.Xaml;
using QuizSync.Provider;

namespace QuizSync.App;

/// <summary>Phase 6 外壳的入口。</summary>
public partial class App : Application, IDisposable
{
    /// <summary>全局热键的槽位号（每个槽位固定一个 id，见 `HotkeyService` 的说明）。</summary>
    private const int CaptureSlot = 1;

    /// <summary>F8：截屏识别。与 1.1.0 一致的键位（`AGENTS.md` M46：F8 截屏识别 / F9 多页）。</summary>
    private const uint VkF8 = 0x77;

    private Window? _window;
    private HotkeyService? _hotkeys;
    private FloatingBall? _ball;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var window = new MainWindow();
        _window = window;
        // 窗口关掉就把热键注销掉：`RegisterHotKey` 是**系统级**的，不显式注销会留在系统里。
        window.Closed += (_, _) => Dispose();
        window.Activate();

        RegisterGlobalHotkey();
        ShowFloatingBall();
    }

    /// <summary>
    /// 注册全局热键。内核（`HotkeyService`）早就写好了 —— 它按 M45f 的结论实现：
    /// **后台线程一次 `await` 都不做**（同步 `PeekMessageW` + `Sleep`），并且每 2 秒自检补回注册。
    /// 原来那个「长按/线程漂移导致热键悄悄失效」的坑都在内核里处理掉了，这里只负责接线。
    ///
    /// 注册失败**不静默**：把原因写到窗口标题后缀上（这一版还没有日志面板，标题是最容易看见的地方）。
    /// </summary>
    private void RegisterGlobalHotkey()
    {
        try
        {
            _hotkeys = new HotkeyService();
            _hotkeys.Triggered += slot =>
            {
                if (slot != CaptureSlot)
                {
                    return;
                }

                // 热键回调来自后台线程，必须切回 UI 线程再动 XAML。
                // 与悬浮球走同一个入口（`TriggerCapture`）—— 两条路的行为不许分叉。
                _window?.DispatcherQueue.TryEnqueue(TriggerCapture);
            };

            var chord = new HotkeyChord("F8", VkF8, HotkeyModifiers.None);
            var result = _hotkeys.Register(CaptureSlot, chord);
            if (result != HotkeyRegisterResult.Ok)
            {
                _window!.Title = $"{AppWindowScope.Title}（热键 F8 未生效：{_hotkeys.LastRejectReason ?? result.ToString()}）";
            }
        }
        catch (Exception error)
        {
            _window!.Title = $"{AppWindowScope.Title}（热键注册失败：{error.Message}）";
        }
    }

    /// <summary>
    /// 悬浮球（原生分层窗口）。点击它就等于按一次 F8 —— **两条路走同一个入口**，
    /// 所以「点了球」与「按了热键」的行为不会分叉。
    ///
    /// 失败**不静默**：球建不起来时把原因写进窗口标题（这一版还没有日志面板）。
    /// </summary>
    private void ShowFloatingBall() => ApplyBallSettings();

    /// <summary>
    /// 按当前设置重建悬浮球。**设置页改完就调它** —— 这样「改了设置立刻生效」，
    /// 不用重启应用（1.1.0 的用户反馈里，「调了没反应」是最早被报上来的那类问题）。
    /// </summary>
    internal void ApplyBallSettings()
    {
        // 先把旧的收掉：尺寸/透明度变了必须重建（分层窗口的位图是按尺寸建的）。
        _ball?.Dispose();
        _ball = null;

        var settings = BallSettings.Load();
        if (!settings.Enabled)
        {
            return;
        }

        try
        {
            _ball = new FloatingBall(
                _window!.DispatcherQueue,
                TriggerCapture,
                settings.Diameter,
                settings.Opacity,
                settings.Stroke ? settings.StrokeWidth : 0,
                settings.X,
                settings.Y,
                (x, y) =>
                {
                    // 只更新位置，别把界面上的其他改动覆盖掉（设置页可能刚改过大小）。
                    var current = BallSettings.Load();
                    current.X = x;
                    current.Y = y;
                    current.Save();
                });
            _ball.Show();
        }
        catch (Exception error)
        {
            _ball?.Dispose();
            _ball = null;
            _window!.Title = $"{AppWindowScope.Title}（悬浮球未显示：{error.Message}）";
        }
    }

    /// <summary>热键与悬浮球共用的触发路径：跳到截屏搜题页并立刻开跑。</summary>
    private void TriggerCapture()
    {
        if (_window?.Content is Microsoft.UI.Xaml.Controls.Frame frame)
        {
            frame.Navigate(typeof(Pages.SolvePage), true);
        }
    }

    /// <summary>注销全局热键、销毁悬浮球（两者都是系统级的，退出时必须显式清理）。</summary>
    public void Dispose()
    {
        _hotkeys?.Dispose();
        _hotkeys = null;
        _ball?.Dispose();
        _ball = null;
        GC.SuppressFinalize(this);
    }
}
