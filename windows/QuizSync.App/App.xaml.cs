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

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var window = new MainWindow();
        _window = window;
        // 窗口关掉就把热键注销掉：`RegisterHotKey` 是**系统级**的，不显式注销会留在系统里。
        window.Closed += (_, _) => Dispose();
        window.Activate();

        RegisterGlobalHotkey();
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
                _window?.DispatcherQueue.TryEnqueue(() =>
                {
                    if (_window?.Content is Microsoft.UI.Xaml.Controls.Frame frame)
                    {
                        // 参数 true = 进来就开跑（用户按 F8 就是想立刻识别）。
                        frame.Navigate(typeof(Pages.SolvePage), true);
                    }
                });
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

    /// <summary>注销全局热键（`RegisterHotKey` 是系统级的，不注销会残留）。</summary>
    public void Dispose()
    {
        _hotkeys?.Dispose();
        _hotkeys = null;
        GC.SuppressFinalize(this);
    }
}
