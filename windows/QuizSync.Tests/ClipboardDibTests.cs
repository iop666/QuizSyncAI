using QuizSync.Provider;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 剪贴板 DIB 解析。用例直接构造 DIB 字节（真实剪贴板内容无法在测试里稳定复现），
/// 覆盖老实现踩过的每一类：BI_BITFIELDS 掩码、负 biHeight（自上而下）、24bpp 行对齐、
/// V5 头、以及各种非法输入。
/// </summary>
public sealed class ClipboardDibTests
{
    /// <summary>造一个 DIB：headerSize 字节头 + 像素行。</summary>
    private static byte[] Build(
        int width, int height, ushort bitCount, uint compression, byte[] pixelRows,
        uint headerSize = 40, uint[]? masks = null, bool v5 = false)
    {
        var totalHeader = v5 ? 124 : (int)headerSize;
        // 40 字节头 + BI_BITFIELDS：三个掩码紧跟在头后面（占 12 字节），像素从它之后才开始 ——
        // 写到头后面会把掩码覆盖掉（第一版助手就是这么错的）。
        var maskBytes = compression == 3 && headerSize == 40 ? 12 : 0;
        var dib = new byte[totalHeader + maskBytes + pixelRows.Length];
        void U32(int offset, uint value) => BitConverter.GetBytes(value).CopyTo(dib, offset);
        void I32(int offset, int value) => BitConverter.GetBytes(value).CopyTo(dib, offset);
        void U16(int offset, ushort value) => BitConverter.GetBytes(value).CopyTo(dib, offset);

        U32(0, headerSize);
        I32(4, width);
        I32(8, height);
        U16(12, 1); // planes
        U16(14, bitCount);
        U32(16, compression);
        if (masks is not null)
        {
            // 40 字节头的掩码紧跟其后；V4/V5 头的掩码在头内部 40 起。
            var m = headerSize >= 52 ? 40 : (int)headerSize;
            U32(m, masks[0]);
            U32(m + 4, masks[1]);
            U32(m + 8, masks[2]);
            if (masks.Length > 3)
            {
                U32(m + 12, masks[3]);
            }
        }

        pixelRows.CopyTo(dib, totalHeader + maskBytes);
        return dib;
    }

    /// <summary>一行 32bpp 像素（每像素 4 字节，BGRX 顺序即 BI_RGB 的排布）。</summary>
    private static byte[] Row32(params (byte B, byte G, byte R, byte A)[] pixels)
    {
        var row = new byte[pixels.Length * 4];
        for (var i = 0; i < pixels.Length; i++)
        {
            row[i * 4] = pixels[i].B;
            row[(i * 4) + 1] = pixels[i].G;
            row[(i * 4) + 2] = pixels[i].R;
            row[(i * 4) + 3] = pixels[i].A;
        }

        return row;
    }

    [Fact]
    public void BiRgb_32bpp_bottom_up_is_flipped_to_top_down()
    {
        // 两行：DIB 里第一行是「图像最下面一行」。
        var bottom = Row32((10, 20, 30, 0xFF));
        var top = Row32((40, 50, 60, 0xFF));
        var dib = Build(1, 2, 32, 0, [.. bottom, .. top]);

        var image = ClipboardDib.TryParse(dib);

        Assert.NotNull(image);
        Assert.Equal(1, image!.Width);
        Assert.Equal(2, image.Height);
        // 自上而下：第一行应是最初的「上面那行」，且通道是 B,G,R。
        Assert.Equal([40, 50, 60, 255], image.Bgra[..4]);
        Assert.Equal([10, 20, 30, 255], image.Bgra[4..8]);
    }

    [Fact]
    public void Negative_height_means_top_down_and_needs_sign_extension()
    {
        var first = Row32((1, 2, 3, 0xFF));
        var second = Row32((4, 5, 6, 0xFF));
        var dib = Build(1, -2, 32, 0, [.. first, .. second]);

        var image = ClipboardDib.TryParse(dib);

        Assert.NotNull(image);
        Assert.Equal(2, image.Height);      // 符号扩展后 |height| = 2（不扩展会读成天文数字）
        Assert.Equal([1, 2, 3, 255], image!.Bgra[..4]);   // 第一行就是第一行，不翻转
        Assert.Equal([4, 5, 6, 255], image.Bgra[4..8]);
    }

    [Fact]
    public void BiBitfields_with_masks_reads_channels_by_mask()
    {
        // 掩码把通道挪了位：R 在高位、B 在低位（这里故意用与 BI_RGB 不同的排布）。
        uint[] masks = [0x000000FF, 0x0000FF00, 0x00FF0000]; // R, G, B
        // 值 0x00_33_22_11 → R=0x11(17) G=0x22(34) B=0x33(51)
        var row = Row32((0x11, 0x22, 0x33, 0));
        var dib = Build(1, 1, 32, 3, row, masks: masks);

        var image = ClipboardDib.TryParse(dib);

        Assert.NotNull(image);
        // 输出永远是 BGRA：B 来自 B 掩码…
        Assert.Equal([51, 34, 17, 255], image!.Bgra[..4]);
    }

    [Fact]
    public void Bitfields_with_alpha_mask_uses_it()
    {
        uint[] masks = [0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000];
        var row = Row32((0x20, 0x40, 0x60, 0x80));
        var dib = Build(1, 1, 32, 3, row, headerSize: 124, masks: masks, v5: true); // V5 头自己声明 124

        var image = ClipboardDib.TryParse(dib);

        Assert.Equal(0x80, image!.Bgra[3]);
    }

    [Fact]
    public void Mask_that_is_not_byte_aligned_is_scaled()
    {
        // 5 位红通道（常见于 16bpp，这里用 32bpp 载体验证缩放逻辑）。
        uint[] masks = [0x0000001F, 0x000003E0, 0x00007C00];
        var row = Row32((0x1F, 0, 0, 0)); // R 通道拉满
        var dib = Build(1, 1, 32, 3, row, masks: masks);

        var image = ClipboardDib.TryParse(dib);

        Assert.Equal(255, image!.Bgra[2]); // 拉满 → 255
    }

    [Fact]
    public void BiRgb_24bpp_pixel_order_is_bgr_and_rows_are_aligned()
    {
        // 两行，宽 1：每行 3 字节像素 + 1 字节补齐 = 4 字节。
        byte[] rows =
        [
            0x10, 0x20, 0x30, 0x00, // 底行：B=0x10 G=0x20 R=0x30
            0x40, 0x50, 0x60, 0x00, // 顶行
        ];
        var dib = Build(1, 2, 24, 0, rows);

        var image = ClipboardDib.TryParse(dib);

        Assert.NotNull(image);
        Assert.Equal([0x40, 0x50, 0x60, 255], image!.Bgra[..4]); // 顶行、BGRA
        Assert.Equal([0x10, 0x20, 0x30, 255], image.Bgra[4..8]);
    }

    [Fact]
    public void V5_header_is_accepted()
    {
        var row = Row32((7, 8, 9, 0xFF));
        var dib = Build(1, 1, 32, 0, row, headerSize: 124, v5: true);

        var image = ClipboardDib.TryParse(dib);

        Assert.NotNull(image);
        Assert.Equal([7, 8, 9, 255], image!.Bgra[..4]);
    }

    [Theory]
    [InlineData(0)]      // 空
    [InlineData(20)]     // 比头还短
    public void Too_short_buffer_is_rejected(int length)
    {
        Assert.Null(ClipboardDib.TryParse(new byte[length]));
    }

    [Fact]
    public void Illegal_headers_are_rejected()
    {
        var row = Row32((1, 2, 3, 0));

        Assert.Null(ClipboardDib.TryParse(Build(0, 1, 32, 0, row)));            // 宽 0
        Assert.Null(ClipboardDib.TryParse(Build(1, 0, 32, 0, row)));            // 高 0
        Assert.Null(ClipboardDib.TryParse(Build(1, 1, 16, 0, row)));            // 16bpp 不支持
        Assert.Null(ClipboardDib.TryParse(Build(1, 1, 32, 4, row)));            // BI_JPEG 之类的压缩
        var badPlanes = Build(1, 1, 32, 0, row);
        BitConverter.GetBytes((ushort)2).CopyTo(badPlanes, 12);
        Assert.Null(ClipboardDib.TryParse(badPlanes));                          // planes != 1
    }

    [Fact]
    public void Truncated_pixel_data_is_rejected()
    {
        var row = Row32((1, 2, 3, 0));
        var dib = Build(4, 4, 32, 0, row); // 声称 4×4，实际只给了一行

        Assert.Null(ClipboardDib.TryParse(dib));
    }

    [Fact]
    public void Bitfields_header_without_masks_is_rejected()
    {
        var row = Row32((1, 2, 3, 0));
        var dib = Build(1, 1, 32, 3, row, headerSize: 40); // 没有掩码
        // 手工把长度截成刚好没有掩码区
        var truncated = dib[..40];
        Assert.Null(ClipboardDib.TryParse(truncated));
    }
}
