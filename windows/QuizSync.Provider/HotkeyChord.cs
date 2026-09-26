namespace QuizSync.Provider;

/// <summary>Win32 修饰键位（与 `RegisterHotKey` 的 MOD_* 一致）。</summary>
[Flags]
public enum HotkeyModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Win = 0x0008,
    NoRepeat = 0x4000,
}

/// <summary>一个全局热键组合（虚拟键码 + 修饰键）。</summary>
public sealed record HotkeyChord(string Label, uint VirtualKey, HotkeyModifiers Modifiers)
{
    public bool IsFunctionKey => VirtualKey is >= 0x70 and <= 0x87; // F1–F24

    public override string ToString() => Label;
}

/// <summary>
/// 候选热键的**拒绝规则**（移植自桌面端 `hotkeyRejectReason`）。
/// 纯函数，可单测：这些规则是「用户按了没反应」类投诉的第一道闸。
/// </summary>
public static class HotkeyRules
{
    /// <summary>返回 null 表示这个组合可以做全局热键；否则是给用户看的原因。</summary>
    public static string? RejectReason(HotkeyChord chord)
    {
        ArgumentNullException.ThrowIfNull(chord);

        if (chord.VirtualKey == 0)
        {
            return "只按修饰键不算组合键";
        }

        // 只按修饰键：等价于没有主键。
        if (chord.VirtualKey is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5)
        {
            return "只按修饰键不算组合键";
        }

        var realModifiers = chord.Modifiers & (HotkeyModifiers.Alt | HotkeyModifiers.Control | HotkeyModifiers.Shift | HotkeyModifiers.Win);
        if (realModifiers == HotkeyModifiers.None && !chord.IsFunctionKey)
        {
            return "单按这个键会抢走普通打字，请加一个修饰键（Ctrl / Alt / Shift / Win）；单按 F1–F12 可以";
        }

        return null;
    }
}
