using QuizSync.Provider;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 截屏与「藏窗口再恢复」。
///
/// 恢复计划是**纯函数**（真实窗口层叠关系在 CI 里没法复现）；截屏则在本机真跑一次
/// （拿得到尺寸与像素，不断言具体画面内容 —— 那取决于截屏时屏幕上是什么）。
/// </summary>
public sealed class ScreenCaptureTests
{
    [Fact]
    public void Restore_plan_inserts_back_below_the_remembered_window()
    {
        var plan = AppWindowScope.PlanRestore(previousAbove: 0x1234, wasForeground: false);

        Assert.Equal(0x1234, plan.InsertAfter); // 插回原来上面那个窗口之下
        Assert.False(plan.RestoreFocus);
        Assert.Equal(0x0001u | 0x0002u | 0x0010u | 0x0040u, plan.Flags); // NOSIZE|NOMOVE|NOACTIVATE|SHOWWINDOW
    }

    [Fact]
    public void Restore_plan_goes_to_top_when_there_was_nothing_above()
    {
        var plan = AppWindowScope.PlanRestore(previousAbove: 0, wasForeground: false);

        Assert.Equal(0, plan.InsertAfter); // HWND_TOP
        Assert.False(plan.RestoreFocus);
    }

    [Fact]
    public void Focus_is_restored_only_when_we_were_the_foreground_window()
    {
        Assert.True(AppWindowScope.PlanRestore(0, wasForeground: true).RestoreFocus);
        Assert.False(AppWindowScope.PlanRestore(0x1234, wasForeground: false).RestoreFocus);
    }

    [Fact]
    public void Missing_window_title_yields_zero_and_action_still_runs()
    {
        var title = $"QuizSync 不存在的窗口标题 {Guid.NewGuid():N}";
        Assert.Equal(IntPtr.Zero, AppWindowScope.FindAppWindow(title));

        var ran = false;
        var result = AppWindowScope.HideWhile(title, () => { ran = true; return 42; }, settleMs: 0);

        Assert.True(ran);
        Assert.Equal(42, result);
    }

    [Fact]
    public void Capturing_a_region_returns_top_down_bgra_of_the_right_size()
    {
        var bounds = ScreenCapture.VirtualScreen();
        Assert.True(bounds.Width > 0 && bounds.Height > 0, $"虚拟桌面尺寸异常：{bounds}");

        // 从虚拟桌面左上角截一小块（一定在屏幕内）。
        var image = ScreenCapture.CaptureRegion(bounds.X, bounds.Y, 320, 200);

        Assert.NotNull(image);
        Assert.Equal(320, image!.Width);
        Assert.Equal(200, image.Height);
        Assert.Equal(320 * 200 * 4, image.Bgra.Length);

        // 屏幕上不可能整块都是纯黑（锁屏除外时也只是不断言内容，这里只证明真的拿到了像素）。
        var nonZero = image.Bgra.Count(b => b != 0);
        Assert.True(nonZero > 0, "截屏结果全是 0 字节，说明 BitBlt 没真的把像素拷出来");
    }

    [Fact]
    public void Illegal_regions_are_rejected_without_touching_gdi()
    {
        Assert.Null(ScreenCapture.CaptureRegion(0, 0, 0, 100));
        Assert.Null(ScreenCapture.CaptureRegion(0, 0, 100, -5));
    }

    [Fact]
    public void Full_virtual_screen_capture_matches_the_reported_size()
    {
        var bounds = ScreenCapture.VirtualScreen();
        var image = ScreenCapture.CaptureVirtualScreen();

        Assert.NotNull(image);
        Assert.Equal(bounds.Width, image!.Width);
        Assert.Equal(bounds.Height, image.Height);
    }
}
