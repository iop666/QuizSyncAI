using QuizSync.Provider;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 全局热键：拒绝规则是纯函数（可单测），注册/自检在本机真跑一次
/// （用不常见的组合，避免和真实应用抢键）。
/// </summary>
public sealed class HotkeyTests
{
    private static HotkeyChord Chord(uint vk, HotkeyModifiers modifiers, string label = "test") =>
        new(label, vk, modifiers);

    [Theory]
    [InlineData(0x71, "F2")] // 单按功能键可以
    [InlineData(0x7B, "F12")]
    public void Plain_function_keys_are_allowed(uint vk, string label)
    {
        Assert.Null(HotkeyRules.RejectReason(Chord(vk, HotkeyModifiers.None, label)));
    }

    [Fact]
    public void Plain_letter_or_digit_is_rejected_with_an_actionable_message()
    {
        var reason = HotkeyRules.RejectReason(Chord(0x51, HotkeyModifiers.None, "Q"));
        Assert.NotNull(reason);
        Assert.Contains("请加一个修饰键", reason!, StringComparison.Ordinal);
        Assert.Contains("单按 F1–F12 可以", reason!, StringComparison.Ordinal);
    }

    [Fact]
    public void Modifier_only_chords_are_rejected()
    {
        Assert.Equal("只按修饰键不算组合键", HotkeyRules.RejectReason(Chord(0x11, HotkeyModifiers.Control, "Ctrl")));
        Assert.Equal("只按修饰键不算组合键", HotkeyRules.RejectReason(Chord(0x5B, HotkeyModifiers.Win, "Win")));
        Assert.Equal("只按修饰键不算组合键", HotkeyRules.RejectReason(Chord(0x00, HotkeyModifiers.None, "空")));
    }

    [Fact]
    public void Chord_with_a_modifier_is_allowed()
    {
        Assert.Null(HotkeyRules.RejectReason(Chord(0x51, HotkeyModifiers.Control | HotkeyModifiers.Alt, "Ctrl+Alt+Q")));
    }

    [Fact]
    public void Registering_a_rare_chord_succeeds_and_conflicts_are_reported()
    {
        // F24 极少被占用；即使被占用也只影响这一条断言的前提，返回码本身要如实反映。
        var chord = Chord(0x87, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift, "Ctrl+Alt+Shift+F24");

        using var service = new HotkeyService();
        var first = service.Register(1, chord);
        Assert.Equal(HotkeyRegisterResult.Ok, first);

        // 第二个服务抢同一个组合 → 必须如实报「已被占用」，不能假装成功。
        using var other = new HotkeyService();
        using var gate = new ManualResetEventSlim(false);
        var second = other.Register(1, chord);
        Assert.Equal(HotkeyRegisterResult.AlreadyRegistered, second);

        // 注销后可以被别人拿走。
        service.Unregister(1);
        Assert.Equal(HotkeyRegisterResult.Ok, other.Register(1, chord));
    }

    [Fact]
    public void Rejected_chords_never_touch_win32_and_keep_the_reason()
    {
        using var service = new HotkeyService();
        var result = service.Register(3, Chord(0x41, HotkeyModifiers.None, "A"));

        Assert.Equal(HotkeyRegisterResult.Rejected, result);
        Assert.NotNull(service.LastRejectReason);
    }

    [Fact]
    public void Self_check_runs_and_reports_no_lost_registrations()
    {
        var chord = Chord(0x86, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift, "Ctrl+Alt+Shift+F23");
        using var service = new HotkeyService(selfCheckInterval: TimeSpan.FromMilliseconds(120));

        Assert.Equal(HotkeyRegisterResult.Ok, service.Register(7, chord));

        // 等几次自检：注册没丢的话，每次自检的「再注册」都应该失败于 1409 → 补回计数保持 0。
        var deadline = DateTimeOffset.UtcNow.AddSeconds(3);
        while (service.SelfChecks < 3 && DateTimeOffset.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        Assert.True(service.SelfChecks >= 3, $"自检没有按周期跑起来（只跑了 {service.SelfChecks} 次）");
        Assert.Equal(0, service.LostAndRestored);
    }
}
