using System.Runtime.InteropServices;

namespace QuizSync.Provider;

/// <summary>恢复窗口时的三件事：插到谁后面、用什么标志、要不要还焦点。</summary>
public sealed record RestorePlan(long InsertAfter, uint Flags, bool RestoreFocus);

/// <summary>
/// 截屏前后隐藏/恢复**本应用自己**的窗口（SPEC 2.1：不能把 UI 拍进发给 AI 的图里）。
///
/// 这一段是用户投诉逼出来的，逐字保留（见 `AGENTS.md` 与桌面端 `screen_capture.dart`）：
/// - 定位窗口只认标题（`FindWindow`），**不用** `GetActiveWindow()`（常驻后台时返回 0，
///   窗口不会被藏 → 上一次的答案被截进图里）也**不用** `GetForegroundWindow()`
///   （热键在别的应用上按下时那是别人的窗口，会把用户的浏览器藏起来）；
/// - 藏之前记两件事：**我们是不是前台**（只有是，恢复时才还焦点）、**紧挨上面那个窗口**
///   （恢复时插回它下面）。只靠 `SW_SHOWNOACTIVATE` 不抢焦点但仍会把窗口提到同级最上层，
///   用悬浮球时人在别的应用里，观感依旧是「界面跳出来了」；
/// - 窗口标题**只有一个来源**（老实现改中文名时漏改一个字面量，导致窗口根本没被藏）。
/// </summary>
public static class AppWindowScope
{
    /// <summary>
    /// 应用窗口标题 —— **全仓库唯一来源**。
    /// 老实现就是因为多了一份字面量（改中文名时漏改），导致 `FindWindow` 返回 0、窗口从来没被藏过，
    /// 上一次的答案被拍进发给 AI 的图里（见 `AGENTS.md` M31）。窗口构造时用这个常量覆盖 XAML 里的写法。
    /// </summary>
    public const string Title = "AI 双端搜题";

    private const int GwlHwndPrev = 3;
    private const int SwHide = 0;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private static readonly IntPtr HwndTop = IntPtr.Zero;

    /// <summary>按标题找窗口（标题必须来自**唯一**的那个常量）。</summary>
    public static IntPtr FindAppWindow(string title) => FindWindowW(null, title);

    public static bool IsVisible(IntPtr hwnd) => hwnd != IntPtr.Zero && IsWindowVisible(hwnd);

    /// <summary>
    /// 纯函数：算出恢复时的动作（可单测 —— 真实窗口行为在 CI 里没法复现）。
    /// </summary>
    public static RestorePlan PlanRestore(long previousAbove, bool wasForeground)
    {
        // 原来就在最上层（没有「上面那个窗口」）→ 插回最上层；否则插回它下面，层叠关系不变。
        var insertAfter = previousAbove == 0 ? 0L : previousAbove;
        var flags = SwpNoMove | SwpNoSize | SwpNoActivate | SwpShowWindow;
        return new RestorePlan(insertAfter, flags, wasForeground);
    }

    /// <summary>
    /// 藏窗口 → 执行 action → 恢复。窗口不可见或找不到时**原样执行**（不假装藏过）。
    /// </summary>
    public static T HideWhile<T>(string windowTitle, Func<T> action, int settleMs = 180)
    {
        ArgumentNullException.ThrowIfNull(action);
        var hwnd = FindAppWindow(windowTitle);
        if (hwnd == IntPtr.Zero || !IsVisible(hwnd))
        {
            return action();
        }

        var wasForeground = GetForegroundWindow() == hwnd;
        var previousAbove = GetWindow(hwnd, GwlHwndPrev).ToInt64();

        ShowWindow(hwnd, SwHide);
        // 等 compositor 真正把窗口内容移走（不等会拍到残影）。
        Thread.Sleep(settleMs);

        try
        {
            return action();
        }
        finally
        {
            var plan = PlanRestore(previousAbove, wasForeground);
            SetWindowPos(
                hwnd,
                plan.InsertAfter == 0 ? HwndTop : new IntPtr(plan.InsertAfter),
                0, 0, 0, 0,
                plan.Flags);

            if (plan.RestoreFocus)
            {
                SetForegroundWindow(hwnd);
            }
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowW(string? className, string windowName);

    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
}
