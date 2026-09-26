using System.Runtime.InteropServices;

namespace QuizSync.Provider;

/// <summary>注册结果（把 Win32 的失败原因翻成人话，不静默失败）。</summary>
public enum HotkeyRegisterResult
{
    Ok,
    AlreadyRegistered,   // 1409：别人（或自己旧注册）占着
    Rejected,            // 规则不允许（见 HotkeyRules）
    Failed,              // 其他 Win32 失败
}

/// <summary>
/// 全局热键服务：**一条专用线程 + 自己的消息泵**（计划 §7.3 的「专用消息线程 + RegisterHotKey」）。
///
/// 为什么必须这样（老实现踩透的两条）：
/// - `RegisterHotKey` 把注册绑在**线程**的消息队列上，而线程退出 ≠ 注销：老实现里 isolate 让出执行权后
///   VM 把工作换到别的池线程，持有注册的那条线程被收走 → 注册**悄悄消失**，进程还活着、界面还写着 F8，
///   按下去毫无反应，Win32 **不给任何通知**；
/// - 所以这里：① 消息泵**一次 await 都不做**（同步 `PeekMessageW` + `Sleep`）；② 每 2 秒做一次
///   **同 id 再注册自检**（还持有必然失败于 1409；成功即说明丢了，顺手补回来）。
/// </summary>
public sealed class HotkeyService : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const int ErrorHotkeyAlreadyRegistered = 1409;
    private const uint PmRemove = 0x0001;
    private const uint PmNoRemove = 0x0000;

    private readonly object _gate = new();
    private readonly Dictionary<int, HotkeyChord> _slots = [];
    private readonly Thread _thread;
    private readonly CancellationTokenSource _stopping = new();
    private readonly TimeSpan _selfCheckInterval;
    private int _selfChecks;
    private int _lostAndRestored;

    public HotkeyService(TimeSpan? selfCheckInterval = null)
    {
        _selfCheckInterval = selfCheckInterval ?? TimeSpan.FromSeconds(2);
        _thread = new Thread(PumpLoop) { IsBackground = true, Name = "QuizSync.Hotkeys" };
        // 这个服务只服务 Windows（本工程就是 Windows 内核）；分析器需要显式声明平台。
        if (OperatingSystem.IsWindows())
        {
            _thread.SetApartmentState(ApartmentState.STA);
        }

        _thread.Start();
    }

    /// <summary>触发了哪个槽位（在消息泵线程上回调，实现方自己切出去）。</summary>
    public event Action<int>? Triggered;

    public int SelfChecks => _selfChecks;

    /// <summary>自检发现「注册丢了」并补回来的次数（长期应为 0；不为 0 就是出了问题）。</summary>
    public int LostAndRestored => _lostAndRestored;

    /// <summary>注册一批槽位（槽位 id 由调用方固定分配，绝不复用）。</summary>
    public HotkeyRegisterResult Register(int slotId, HotkeyChord chord)
    {
        ArgumentNullException.ThrowIfNull(chord);
        if (HotkeyRules.RejectReason(chord) is { } reason)
        {
            LastRejectReason = reason;
            return HotkeyRegisterResult.Rejected;
        }

        lock (_gate)
        {
            _slots[slotId] = chord;
        }

        // 注册必须在泵线程上做（线程级资源就要在同一线程申请）。
        return RunOnPump(() =>
        {
            if (!RegisterHotKey(IntPtr.Zero, slotId, (uint)chord.Modifiers, chord.VirtualKey))
            {
                return Marshal.GetLastWin32Error() == ErrorHotkeyAlreadyRegistered
                    ? HotkeyRegisterResult.AlreadyRegistered
                    : HotkeyRegisterResult.Failed;
            }

            return HotkeyRegisterResult.Ok;
        });
    }

    public void Unregister(int slotId)
    {
        lock (_gate)
        {
            _slots.Remove(slotId);
        }

        RunOnPump(() =>
        {
            _ = UnregisterHotKey(IntPtr.Zero, slotId);
            return HotkeyRegisterResult.Ok;
        });
    }

    public string? LastRejectReason { get; private set; }

    /// <summary>把一段工作排到泵线程执行并等结果（同步等待，调用方线程不受影响）。</summary>
    private T RunOnPump<T>(Func<T> work)
    {
        if (Thread.CurrentThread == _thread)
        {
            return work();
        }

        T result = default!;
        using var done = new ManualResetEventSlim(false);
        _pending.Enqueue(() =>
        {
            try
            {
                result = work();
            }
            catch (Exception)
            {
                // 泵线程不能被业务异常带走：失败按默认值返回，由调用方的返回值判定。
            }
            finally
            {
                done.Set();
            }
        });

        done.Wait(TimeSpan.FromSeconds(5));
        return result;
    }

    private readonly System.Collections.Concurrent.ConcurrentQueue<Action> _pending = new();

    private void PumpLoop()
    {
        var lastSelfCheck = Environment.TickCount64;
        while (!_stopping.IsCancellationRequested)
        {
            while (_pending.TryDequeue(out var work))
            {
                work();
            }

            // 同步抽消息：不用 await（线程要稳）。
            while (PeekMessageW(out var message, IntPtr.Zero, 0, 0, PmRemove))
            {
                if (message.Message == WmHotkey)
                {
                    Triggered?.Invoke(message.WParam.ToInt32());
                }
            }

            var now = Environment.TickCount64;
            if (now - lastSelfCheck >= (long)_selfCheckInterval.TotalMilliseconds)
            {
                lastSelfCheck = now;
                SelfCheck();
            }

            Thread.Sleep(15);
        }

        // 退出前显式注销全部（不依赖线程结束）。
        List<int> ids;
        lock (_gate)
        {
            ids = [.. _slots.Keys];
        }

        foreach (var id in ids)
        {
            _ = UnregisterHotKey(IntPtr.Zero, id);
        }
    }

    /// <summary>
    /// 每 2 秒自检：拿同一个 id 再注册一次 —— 还持有必然 1409；**成功即说明注册丢了**，顺手补回来。
    /// </summary>
    private void SelfCheck()
    {
        List<KeyValuePair<int, HotkeyChord>> snapshot;
        lock (_gate)
        {
            snapshot = [.. _slots];
        }

        _selfChecks++;
        foreach (var (slotId, chord) in snapshot)
        {
            if (RegisterHotKey(IntPtr.Zero, slotId, (uint)chord.Modifiers, chord.VirtualKey))
            {
                // 竟然成功：说明原来的注册已经不在系统里了。这一次调用已经把槽位补回去了。
                _lostAndRestored++;
            }
        }
    }

    public void Dispose()
    {
        _stopping.Cancel();
        _thread.Join(TimeSpan.FromSeconds(3));
        _stopping.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Msg
    {
        public IntPtr Hwnd;
        public uint Message;
        public IntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public int PointX;
        public int PointY;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool PeekMessageW(out Msg message, IntPtr hwnd, uint filterMin, uint filterMax, uint remove);
}
