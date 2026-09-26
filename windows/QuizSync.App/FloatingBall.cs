using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace QuizSync.App;

/// <summary>
/// Windows 悬浮球（原生**分层窗口**，不是 XAML 窗口）。
///
/// 为什么不用 XAML：球要常驻在桌面最上层、不抢焦点、不进任务栏、不被 Alt+Tab 看到 ——
/// XAML Window 做不到这一套；而且 `AGENTS.md` 里 1.1.0 的实测结论也是
/// 「**不要用第二个引擎/窗口做浮层**，用原生分层窗口」。
///
/// 这里把 1.1.0 踩过的坑直接避开（每条都在 `AGENTS.md` 有记录）：
/// * **像素必须是预乘 alpha 的 BGRA**（`ULW_ALPHA`），否则半透明边缘发黑；
/// * **`UpdateLayeredWindow` 之前必须真的建好 DIB** —— 先给「当前尺寸」赋值会让
///   「尺寸没变就不用建位图」的分支跳过建位图，窗口建出来**什么都没画**（日志一切正常）；
/// * **移动窗口不能只靠 `UpdateLayeredWindow` 的 `pptDst`**，实测位置不跟，要补一次 `SetWindowPos`；
/// * `WS_EX_NOACTIVATE` 防止点球把焦点抢走（用户在别的应用里打字时尤其明显）。
///
/// 本轮只做最小一片：画球 / 拖 / 点击触发识别 / 右键隐藏。
/// 三态外观、设置里的尺寸与描边、按片出图那些留给后续轮次。
/// </summary>
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
internal sealed class FloatingBall : IDisposable
{
    private const string ClassName = "QuizSyncFloatingBall";

    /// <summary>球的直径（物理像素）。来自设置（`BallSettings._diameter`）。</summary>
    private readonly int _diameter;

    /// <summary>整球不透明度（0–255）。用 `BlendFunction.SourceConstantAlpha` 一次搞定，不用逐像素乘。</summary>
    private readonly byte _alpha;

    /// <summary>描边宽度（像素，画在球**外面**）。窗口尺寸 = 球 + 2 × 它。</summary>
    private readonly int _stroke;

    /// <summary>窗口边长。**含两侧描边** —— 1.1.0 踩过「以画布边缘为中心往**里**画」的坑：
    /// 那样环带落在球自己身上、颜色又被球的主色盖住，**等于没有描边**（`AGENTS.md` M16）。
    /// 要向外画就必须把画布做大。</summary>
    private readonly int _windowSize;

    private const int WsExLayered = 0x00080000;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const int WsPopup = unchecked((int)0x80000000);

    private const int WmDestroy = 0x0002;
    private const int WmNchittest = 0x0084;
    private const int WmLbuttondown = 0x0201;
    private const int WmLbuttonup = 0x0202;
    private const int WmRbuttonup = 0x0205;
    private const int WmMousemove = 0x0200;

    private const uint UlwAlpha = 0x00000002;
    private const int SwpNoActivate = 0x0010;
    private const int SwpNoZorder = 0x0004;
    private const int HtClient = 1;
    private const int HtTransparent = unchecked(-1);

    private readonly DispatcherQueue _dispatcher;
    private readonly Action _onClick;
    private readonly Action<int, int>? _onMoved;
    private readonly int? _startX;
    private readonly int? _startY;
    private readonly WndProcDelegate _wndProc; // 必须存字段：委托被 GC 回收后窗口过程就崩了

    private IntPtr _hwnd;
    private IntPtr _memDc;
    private IntPtr _bitmap;
    private IntPtr _oldBitmap;
    private int _bitmapSize;

    private bool _dragging;
    private bool _moved;
    private int _dragOffsetX;
    private int _dragOffsetY;

    internal FloatingBall(
        DispatcherQueue dispatcher,
        Action onClick,
        int diameter,
        int opacityPercent,
        int strokeWidth = 0,
        int? startX = null,
        int? startY = null,
        Action<int, int>? onMoved = null)
    {
        _dispatcher = dispatcher;
        _onClick = onClick;
        _wndProc = WindowProc;
        _diameter = diameter;
        _alpha = (byte)Math.Clamp(opacityPercent * 255 / 100, 0, 255);
        _stroke = Math.Max(0, strokeWidth);
        _windowSize = _diameter + (_stroke * 2);
        _startX = startX;
        _startY = startY;
        _onMoved = onMoved;
    }

    /// <summary>
    /// 把位置夹回可见范围。**这一步不能省**：球的窗口只有几十像素，
    /// 用户拖到屏幕外（或换了更小的显示器）之后就再也点不到它了 —— 那就等于把悬浮球弄丢了。
    /// 留一点边距，保证球**整个**在屏幕内。
    /// </summary>
    private static (int X, int Y) ClampToScreen(int x, int y, int diameter)
    {
        var maxX = Math.Max(0, GetSystemMetrics(0) - diameter);
        var maxY = Math.Max(0, GetSystemMetrics(1) - diameter);
        return (Math.Clamp(x, 0, maxX), Math.Clamp(y, 0, maxY));
    }

    /// <summary>建窗口并显示。失败**不静默**：抛出，由调用处写进窗口标题，用户能看见。</summary>
    internal void Show()
    {
        var module = GetModuleHandle(null);
        var wndClass = new WndClassEx
        {
            cbSize = Marshal.SizeOf<WndClassEx>(),
            lpfnWndProc = _wndProc,
            hInstance = module,
            lpszClassName = ClassName,
        };

        if (RegisterClassEx(ref wndClass) == 0)
        {
            throw new InvalidOperationException($"RegisterClassEx 失败（{Marshal.GetLastWin32Error()}）");
        }

        // 与球直径一致；描边等后续设置项接进来时，窗口尺寸要比球大（向外画描边）。
        _hwnd = CreateWindowEx(
            WsExLayered | WsExToolWindow | WsExNoActivate,
            ClassName,
            "AI 双端搜题 · 悬浮球",
            WsPopup,
            0, 0, _windowSize, _windowSize,
            IntPtr.Zero, IntPtr.Zero, module, IntPtr.Zero);

        if (_hwnd == IntPtr.Zero)
        {
            throw new InvalidOperationException($"CreateWindowEx 失败（{Marshal.GetLastWin32Error()}）");
        }

        // 有记住的位置就用它，否则默认「右侧垂直居中」。
        var (startX, startY) = ClampToScreen(
            _startX ?? (GetSystemMetrics(0) - _diameter - 24),
            _startY ?? (GetSystemMetrics(1) / 2 - _diameter / 2),
            _diameter);
        MoveTo(startX, startY);
        Render();
        ShowWindow(_hwnd, 4 /* SW_SHOWNOACTIVATE */);
    }

    /// <summary>移动到物理坐标。**必须**在渲染之外再 `SetWindowPos` 一次（实测 pptDst 不生效）。</summary>
    private void MoveTo(int x, int y)
    {
        SetWindowPos(_hwnd, IntPtr.Zero, x, y, _windowSize, _windowSize, SwpNoActivate | SwpNoZorder);
    }

    /// <summary>
    /// 画球。**预乘 alpha 的 BGRA**（`ULW_ALPHA` 要的就是这个），
    /// 主色取设计 token 的 brand green `#35693E`，边缘按到圆心的距离做 1 像素抗锯齿。
    /// </summary>
    private void Render()
    {
        if (_hwnd == IntPtr.Zero)
        {
            return;
        }

        // **先建位图，再谈尺寸** —— 这个顺序是 1.1.0 踩过的坑（顺序反了会画出空窗口）。
        if (_bitmap == IntPtr.Zero || _bitmapSize != _windowSize)
        {
            ReleaseBitmap();

            var screenDc = GetDC(IntPtr.Zero);
            _memDc = CreateCompatibleDC(screenDc);
            // 返回值是「成功释放的 DC 数」；这里只有一个，显式丢弃（分析器 CA1806 要求）。
            _ = ReleaseDC(IntPtr.Zero, screenDc);

            var header = new BitmapInfo
            {
                bmiHeader = new BitmapInfoHeader
                {
                    biSize = Marshal.SizeOf<BitmapInfoHeader>(),
                    biWidth = _windowSize,
                    biHeight = -_windowSize, // 负 = 自上而下
                    biPlanes = 1,
                    biBitCount = 32,
                    biCompression = 0, // BI_RGB
                },
            };

            _bitmap = CreateDIBSection(_memDc, ref header, 0, out var bits, IntPtr.Zero, 0);
            if (_bitmap == IntPtr.Zero || bits == IntPtr.Zero)
            {
                throw new InvalidOperationException($"CreateDIBSection 失败（{Marshal.GetLastWin32Error()}）");
            }

            _oldBitmap = SelectObject(_memDc, _bitmap);
            _bitmapSize = _windowSize;

            // 主色 #35693E（设计 token 里的 brand green）→ 预乘 alpha 的 BGRA
            const int r = 0x35, g = 0x69, b = 0x3E;
            var radius = _diameter / 2.0;
            var pixels = new byte[_windowSize * _windowSize * 4];

            // 球心落在更大的画布中心；环带占 [球半径, 球半径 + 描边]。
            var center = _windowSize / 2.0;
            var outerRadius = radius + _stroke;

            // 描边配色：按通道 ×0.72 加深才看得出与球主色的对比（`AGENTS.md` M16 的实测结论）。
            var strokeR = (byte)(r * 0.72);
            var strokeG = (byte)(g * 0.72);
            var strokeB = (byte)(b * 0.72);

            for (var y = 0; y < _windowSize; y++)
            {
                for (var x = 0; x < _windowSize; x++)
                {
                    var dx = x + 0.5 - center;
                    var dy = y + 0.5 - center;
                    var distance = Math.Sqrt((dx * dx) + (dy * dy));
                    var offset = ((y * _windowSize) + x) * 4;

                    byte pixelR, pixelG, pixelB;
                    double alpha;

                    if (distance <= radius - 1)
                    {
                        alpha = 255.0;                       // 球体
                        pixelR = r; pixelG = g; pixelB = b;
                    }
                    else if (distance < radius)
                    {
                        alpha = (radius - distance) * 255.0; // 球缘 1 像素渐隐
                        pixelR = r; pixelG = g; pixelB = b;
                    }
                    else if (_stroke > 0 && distance < outerRadius - 1)
                    {
                        alpha = 255.0;                       // 描边环带
                        pixelR = strokeR; pixelG = strokeG; pixelB = strokeB;
                    }
                    else if (_stroke > 0 && distance < outerRadius)
                    {
                        alpha = (outerRadius - distance) * 255.0; // 描边外缘渐隐
                        pixelR = strokeR; pixelG = strokeG; pixelB = strokeB;
                    }
                    else
                    {
                        alpha = 0.0;                          // 圆外全透明
                        pixelR = 0; pixelG = 0; pixelB = 0;
                    }

                    var a = (byte)alpha;

                    // **预乘**：通道值要乘 alpha/255，否则 ULW_ALPHA 下半透明边缘会发黑。
                    pixels[offset + 0] = (byte)(pixelB * a / 255);
                    pixels[offset + 1] = (byte)(pixelG * a / 255);
                    pixels[offset + 2] = (byte)(pixelR * a / 255);
                    pixels[offset + 3] = a;
                }
            }

            Marshal.Copy(pixels, 0, bits, pixels.Length);
        }

        var size = new SizeStruct { cx = _windowSize, cy = _windowSize };
        var source = new PointStruct { x = 0, y = 0 };
        GetWindowRect(_hwnd, out var rect);
        var destination = new PointStruct { x = rect.left, y = rect.top };
        var blend = new BlendFunction
        {
            BlendOp = 0,          // AC_SRC_OVER
            BlendFlags = 0,
            SourceConstantAlpha = _alpha,
            AlphaFormat = 1,      // AC_SRC_ALPHA
        };

        UpdateLayeredWindow(
            _hwnd, IntPtr.Zero, ref destination, ref size, _memDc, ref source, 0, ref blend, UlwAlpha);

        // 再补一次 SetWindowPos：实测只靠 pptDst 位置会不跟（1.1.0 的实测结论）。
        MoveTo(destination.x, destination.y);
    }

    private IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        switch (message)
        {
            case WmNchittest:
                // 圆外的透明区域不要吃掉鼠标事件（否则球周围一圈「隐形墙」）。
                {
                    // **WM_NCHITTEST 的 lParam 是屏幕坐标**（第三十六轮实测踩到）：
                    // 我原来当成客户区坐标算距离，于是「到圆心 1500 多像素」-> 永远 HTTRANSPARENT
                    // -> 球对整个鼠标透明、点它没任何反应（像素却是好的，所以只看截图会以为是好的）。
                    var point = new PointStruct
                    {
                        x = (short)(lParam.ToInt64() & 0xFFFF),
                        y = (short)((lParam.ToInt64() >> 16) & 0xFFFF),
                    };
                    _ = ScreenToClient(hwnd, ref point);
                    var dx = point.x - (_windowSize / 2.0);
                    var dy = point.y - (_windowSize / 2.0);
                    return Math.Sqrt((dx * dx) + (dy * dy)) <= _windowSize / 2.0
                        ? new IntPtr(HtClient)
                        : new IntPtr(HtTransparent);
                }

            case WmLbuttondown:
                _dragging = true;
                _moved = false;
                GetCursorPos(out var cursor);
                GetWindowRect(hwnd, out var rect);
                _dragOffsetX = cursor.x - rect.left;
                _dragOffsetY = cursor.y - rect.top;
                SetCapture(hwnd);
                return IntPtr.Zero;

            case WmMousemove:
                if (_dragging)
                {
                    GetCursorPos(out var current);
                    _moved = true;
                    MoveTo(current.x - _dragOffsetX, current.y - _dragOffsetY);
                }

                return IntPtr.Zero;

            case WmLbuttonup:
                if (_dragging)
                {
                    _dragging = false;
                    ReleaseCapture();

                    // 拖过就不算点击（与 1.1.0 的判定一致：位移了就是拖）。
                    if (_moved)
                    {
                        // 拖完把位置记下来（存盘在 App 那侧做），下次启动还在原地。
                        if (GetWindowRect(hwnd, out var placed))
                        {
                            var (x, y) = ClampToScreen(placed.left, placed.top, _diameter);
                            _dispatcher.TryEnqueue(() => _onMoved?.Invoke(x, y));
                        }
                    }
                    else
                    {
                        _dispatcher.TryEnqueue(() => _onClick());
                    }
                }

                return IntPtr.Zero;

            case WmRbuttonup:
                // 右键先只做「藏起来」这一件事（三态菜单留后续轮次）。
                ShowWindow(hwnd, 0 /* SW_HIDE */);
                return IntPtr.Zero;

            case WmDestroy:
                return IntPtr.Zero;
        }

        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private void ReleaseBitmap()
    {
        if (_memDc != IntPtr.Zero && _oldBitmap != IntPtr.Zero)
        {
            SelectObject(_memDc, _oldBitmap);
            _oldBitmap = IntPtr.Zero;
        }

        if (_bitmap != IntPtr.Zero)
        {
            DeleteObject(_bitmap);
            _bitmap = IntPtr.Zero;
        }

        if (_memDc != IntPtr.Zero)
        {
            DeleteDC(_memDc);
            _memDc = IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        ReleaseBitmap();

        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }

        UnregisterClass(ClassName, GetModuleHandle(null));
    }

    // ---------------- Win32 ----------------

    private delegate IntPtr WndProcDelegate(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WndClassEx
    {
        public int cbSize;
        public uint style;
        public WndProcDelegate lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public short biPlanes;
        public short biBitCount;
        public int biCompression;
        public int biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public int biClrUsed;
        public int biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader bmiHeader;
        public int bmiColors;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PointStruct
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SizeStruct
    {
        public int cx;
        public int cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WndClassEx wndClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        int exStyle, string className, string windowName, int style,
        int x, int y, int width, int height,
        IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool UnregisterClass(string className, IntPtr instance);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr hwnd, IntPtr after, int x, int y, int width, int height, int flags);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out PointStruct point);

    [DllImport("user32.dll")]
    private static extern bool ScreenToClient(IntPtr hwnd, ref PointStruct point);

    [DllImport("user32.dll")]
    private static extern IntPtr SetCapture(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(
        IntPtr hwnd, IntPtr destinationDc, ref PointStruct destination, ref SizeStruct size,
        IntPtr sourceDc, ref PointStruct source, int colorKey, ref BlendFunction blend, uint flags);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr obj);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateDIBSection(
        IntPtr dc, ref BitmapInfo info, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);
}
