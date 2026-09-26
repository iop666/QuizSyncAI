using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;

namespace QuizSync.Provider;

/// <summary>一次截屏编码的结果。</summary>
public sealed record CapturedJpeg(byte[] Jpeg, string Sha256Hex, int Width, int Height, int SourceWidth, int SourceHeight)
{
    /// <summary>还原成协议里的 `sha256:…` 形态（与 Dart 侧一致）。</summary>
    public string ImageHash => $"sha256:{Sha256Hex}";
}

/// <summary>
/// 截屏 → JPEG（Windows 侧原先缺的那一环）。
///
/// 缺口是第七轮末尾发现的：`AnalysisEngine` / `IAiProvider` 全都吃 `byte[] jpegBytes`，
/// 但整个 Windows 侧**没有任何地方能产出 JPEG** —— `ScreenCapture` 只给 DIB。
/// 于是「截屏 → AI」这条链在 C# 上根本接不起来（Dart 侧当年是靠 `image` 包编码的）。
///
/// 这里用 GDI+（`System.Drawing.Common`）而不是手写 JPEG 编码器：手写要 300+ 行
/// DCT/量化/Huffman，风险全在自己身上；WIC 的 COM 互操作也要 150 行上下。
/// 本应用是 Windows 专用，GDI+ 是这条路上最短且被验证过的一环。
///
/// 三点与 Dart 侧对齐的语义：
/// * **先藏自己的窗口**（`AppWindowScope.HideWhile`）——不能把 UI 拍进发给 AI 的图里；
/// * **长边缩到 [MaxEdge]** —— 3200×2000 的原图对识别没帮助，只会推高 token 与耗时；
/// * 产出 **JPEG + sha256**（`imageHash` 要和协议里的 `images.sha256` 对得上，缓存也用它）。
/// </summary>
[SupportedOSPlatform("windows")]
public static class ScreenJpeg
{
    /// <summary>长边上限（逻辑像素）。文字题在这个尺寸下依然清晰。</summary>
    public const int DefaultMaxEdge = 1600;

    private const int SmXVirtualScreen = 76;
    private const int SmYVirtualScreen = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;

    /// <summary>
    /// 截整块虚拟屏（多显示器时是合并区域）并编码成 JPEG。
    /// [appWindowTitle] 非空时会先把该窗口藏起来再拍（拍完恢复，且不抢焦点）。
    /// </summary>
    public static CapturedJpeg? Capture(
        string? appWindowTitle = null,
        int maxEdge = DefaultMaxEdge,
        long jpegQuality = 82)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxEdge);

        return string.IsNullOrEmpty(appWindowTitle)
            ? CaptureCore(maxEdge, jpegQuality)
            : AppWindowScope.HideWhile(appWindowTitle, () => CaptureCore(maxEdge, jpegQuality));
    }

    private static CapturedJpeg? CaptureCore(int maxEdge, long jpegQuality)
    {
        var left = GetSystemMetrics(SmXVirtualScreen);
        var top = GetSystemMetrics(SmYVirtualScreen);
        var width = GetSystemMetrics(SmCxVirtualScreen);
        var height = GetSystemMetrics(SmCyVirtualScreen);
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        using var full = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        using (var graphics = Graphics.FromImage(full))
        {
            graphics.CopyFromScreen(left, top, 0, 0, new Size(width, height), CopyPixelOperation.SourceCopy);
        }

        // 长边超限就等比缩（缩略图本身也用高质量插值，避免把字缩糊）。
        var scale = Math.Min(1.0, (double)maxEdge / Math.Max(width, height));
        var targetWidth = Math.Max(1, (int)Math.Round(width * scale));
        var targetHeight = Math.Max(1, (int)Math.Round(height * scale));

        using var scaled = scale >= 1.0
            ? null
            : new Bitmap(targetWidth, targetHeight, PixelFormat.Format24bppRgb);
        if (scaled is not null)
        {
            using var graphics = Graphics.FromImage(scaled);
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            graphics.DrawImage(full, 0, 0, targetWidth, targetHeight);
        }

        var output = scaled ?? full;
        using var buffer = new MemoryStream();
        if (jpegQuality > 0)
        {
            var encoder = ImageCodecInfo.GetImageEncoders().First(codec => codec.FormatID == ImageFormat.Jpeg.Guid);
            using var parameters = new EncoderParameters(1);
            using var quality = new EncoderParameter(Encoder.Quality, jpegQuality);
            parameters.Param[0] = quality;
            output.Save(buffer, encoder, parameters);
        }
        else
        {
            output.Save(buffer, ImageFormat.Jpeg);
        }

        var bytes = buffer.ToArray();
        return new CapturedJpeg(
            Jpeg: bytes,
            Sha256Hex: Convert.ToHexStringLower(SHA256.HashData(bytes)),
            Width: output.Width,
            Height: output.Height,
            SourceWidth: width,
            SourceHeight: height);
    }

    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
}
