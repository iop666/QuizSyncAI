using System.Runtime.InteropServices;

namespace QuizSync.Provider;

/// <summary>屏幕区域（物理像素，与 per-monitor DPI aware 进程的口径一致）。</summary>
public sealed record ScreenBounds(int X, int Y, int Width, int Height);

/// <summary>
/// GDI BitBlt 截屏（计划 §7.3：直接 P/Invoke 移植）。
///
/// 输出是**自上而下**的 BGRA（与 <see cref="ClipboardDib"/> 同一个形态，下游只认这一种）。
/// </summary>
public static class ScreenCapture
{
    private const int SrcCopy = 0x00CC0020;
    private const int SmXVirtualScreen = 76;
    private const int SmYVirtualScreen = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;
    private const int DibRgbColors = 0;
    private const int BiRgb = 0;
    private const uint Gdi32DibRgbColors = 0;

    /// <summary>整个虚拟桌面（多显示器时为并集）。</summary>
    public static ScreenBounds VirtualScreen() => new(
        GetSystemMetrics(SmXVirtualScreen),
        GetSystemMetrics(SmYVirtualScreen),
        GetSystemMetrics(SmCxVirtualScreen),
        GetSystemMetrics(SmCyVirtualScreen));

    /// <summary>截取一块区域；失败（句柄/内存/BitBlt）返回 null，不抛。</summary>
    public static DibImage? CaptureRegion(int x, int y, int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        var screenDc = GetDC(IntPtr.Zero);
        if (screenDc == IntPtr.Zero)
        {
            return null;
        }

        var memoryDc = IntPtr.Zero;
        var bitmap = IntPtr.Zero;
        var previous = IntPtr.Zero;
        try
        {
            memoryDc = CreateCompatibleDC(screenDc);
            if (memoryDc == IntPtr.Zero)
            {
                return null;
            }

            // 32bpp、负高度 = 自上而下：直接得到我们要的行序，省一次翻转。
            var header = new BitmapInfoHeader
            {
                Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                Width = width,
                Height = -height,
                Planes = 1,
                BitCount = 32,
                Compression = BiRgb,
            };

            bitmap = CreateDIBSection(memoryDc, ref header, Gdi32DibRgbColors, out var bits, IntPtr.Zero, 0);
            if (bitmap == IntPtr.Zero || bits == IntPtr.Zero)
            {
                return null;
            }

            previous = SelectObject(memoryDc, bitmap);
            if (BitBlt(memoryDc, 0, 0, width, height, screenDc, x, y, SrcCopy) == 0)
            {
                return null;
            }

            var bgra = new byte[width * height * 4];
            Marshal.Copy(bits, bgra, 0, bgra.Length);
            return new DibImage(width, height, bgra);
        }
        finally
        {
            if (memoryDc != IntPtr.Zero && previous != IntPtr.Zero)
            {
                SelectObject(memoryDc, previous);
            }

            if (bitmap != IntPtr.Zero)
            {
                DeleteObject(bitmap);
            }

            if (memoryDc != IntPtr.Zero)
            {
                DeleteDC(memoryDc);
            }

            // ReleaseDC 的返回值是「释放了几次」：为 0 说明没释放成功，但不值得为此中断截屏。
            _ = ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    /// <summary>截整个虚拟桌面。</summary>
    public static DibImage? CaptureVirtualScreen()
    {
        var bounds = VirtualScreen();
        return CaptureRegion(bounds.X, bounds.Y, bounds.Width, bounds.Height);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ClrUsed;
        public uint ClrImportant;
    }

    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);

    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateDIBSection(
        IntPtr hdc, ref BitmapInfoHeader header, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [DllImport("gdi32.dll")]
    private static extern int BitBlt(
        IntPtr destDc, int x, int y, int width, int height, IntPtr srcDc, int srcX, int srcY, int rop);

    /// <summary>仅为让分析器知道这些常量是「DIB 约定」而不是魔法数字。</summary>
    internal static (int DibRgbColors, int BiRgb, int SrcCopy) Conventions =>
        (DibRgbColors, BiRgb, SrcCopy);
}
