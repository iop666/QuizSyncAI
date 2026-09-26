namespace QuizSync.Provider;

/// <summary>解析出来的位图：**自上而下**的 BGRA 像素（每像素 4 字节）。</summary>
public sealed record DibImage(int Width, int Height, byte[] Bgra);

/// <summary>
/// 剪贴板 DIB 解析（移植自桌面端 `parseClipboardDib`）。
///
/// 这一块是实测踩透了的（见 `AGENTS.md` 环境事实）：
/// - 现代截图工具 / 浏览器 / .NET 放进剪贴板的 `CF_DIB` 大多是 **`BI_BITFIELDS`**（掩码给通道），
///   只认 `BI_RGB` 会「每一步都成功、最后静默返回 null」，用户看到的就是「剪贴板监听毫无作用」；
/// - `biHeight` 为负表示**自上而下**，读 int32 **必须真做符号扩展**（否则 -1 变 4294967295，直接判尺寸非法）；
/// - 像素字节数**由 DIB 头自己算**（头 + 掩码 + 4 字节对齐的行 × 高），不要信 `GlobalSize`；
/// - 同一份数据也可能只有 `CF_DIBV5`（124 字节头，掩码在头内部）。
/// </summary>
public static class ClipboardDib
{
    private const uint BiRgb = 0;
    private const uint BiBitfields = 3;

    /// <summary>解析失败返回 null（调用方继续试下一种格式）。</summary>
    public static DibImage? TryParse(byte[] dib)
    {
        ArgumentNullException.ThrowIfNull(dib);
        if (dib.Length < 40)
        {
            return null;
        }

        var headerSize = ReadU32(dib, 0);
        var width = ReadI32(dib, 4);
        var height = ReadI32(dib, 8);
        var planes = ReadU16(dib, 12);
        var bitCount = ReadU16(dib, 14);
        var compression = ReadU32(dib, 16);

        if (headerSize < 40 || width <= 0 || height == 0 || planes != 1)
        {
            return null;
        }

        if (compression != BiRgb && compression != BiBitfields)
        {
            return null;
        }

        if (bitCount != 24 && bitCount != 32)
        {
            return null;
        }

        // 通道掩码：BI_RGB 用约定俗成的 BGR(A) 排布；BI_BITFIELDS 读 DIB 里给的掩码
        // （V4/V5 头在 40..55，40 字节头的三个掩码紧跟其后）。
        uint rMask = 0x00FF0000, gMask = 0x0000FF00, bMask = 0x000000FF;
        var aMask = bitCount == 32 ? 0xFF000000u : 0u;
        if (compression == BiBitfields)
        {
            var m = headerSize >= 52 ? 40u : headerSize;
            if (dib.Length < m + 12)
            {
                return null;
            }

            rMask = ReadU32(dib, (int)m);
            gMask = ReadU32(dib, (int)m + 4);
            bMask = ReadU32(dib, (int)m + 8);
            aMask = headerSize >= 56 && dib.Length >= m + 16 ? ReadU32(dib, (int)m + 12) : 0u;
        }

        var topDown = height < 0;
        var h = Math.Abs(height);
        var bytesPerRow = (((width * bitCount) + 31) / 32) * 4;
        var pixelOffset = (int)headerSize;
        if (compression == BiBitfields && headerSize == 40)
        {
            pixelOffset += 12;
        }

        if (dib.Length < pixelOffset + ((long)bytesPerRow * h))
        {
            return null;
        }

        var bytesPerPixel = bitCount / 8;
        var bgra = new byte[width * h * 4];
        for (var y = 0; y < h; y++)
        {
            var srcY = topDown ? y : h - 1 - y;
            var srcRow = pixelOffset + (srcY * bytesPerRow);
            for (var x = 0; x < width; x++)
            {
                var src = srcRow + (x * bytesPerPixel);
                var value = bytesPerPixel == 4
                    ? ReadU32(dib, src)
                    : (uint)(dib[src] | (dib[src + 1] << 8) | (dib[src + 2] << 16));
                var dst = ((y * width) + x) * 4;
                bgra[dst] = Channel(value, bMask, 0);
                bgra[dst + 1] = Channel(value, gMask, 0);
                bgra[dst + 2] = Channel(value, rMask, 0);
                bgra[dst + 3] = aMask == 0 ? (byte)255 : Channel(value, aMask, 255);
            }
        }

        return new DibImage(width, h, bgra);
    }

    /// <summary>按掩码取出一个通道并归一到 0..255（掩码为 0 时用 fallback）。</summary>
    private static byte Channel(uint value, uint mask, byte fallback)
    {
        if (mask == 0)
        {
            return fallback;
        }

        var shift = 0;
        while (((mask >> shift) & 1) == 0 && shift < 32)
        {
            shift++;
        }

        var maxValue = mask >> shift;
        if (maxValue == 0)
        {
            return fallback;
        }

        var raw = (value & mask) >> shift;
        return (byte)Math.Clamp((int)Math.Round((raw * 255.0) / maxValue), 0, 255);
    }

    private static ushort ReadU16(byte[] b, int o) => (ushort)(b[o] | (b[o + 1] << 8));

    private static uint ReadU32(byte[] b, int o) =>
        (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24));

    /// <summary>有符号 32 位：`biHeight` 为负表示自上而下，必须真做符号扩展。</summary>
    private static int ReadI32(byte[] b, int o) => unchecked((int)ReadU32(b, o));
}
