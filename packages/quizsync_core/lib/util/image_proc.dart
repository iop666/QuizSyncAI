import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 截图后处理（SPEC 2.1）：
/// 统一转 JPEG、长边 ≤ [maxEdge]（默认 1600）、质量 80。
class ProcessedImage {
  final Uint8List jpeg;
  final int width;
  final int height;

  const ProcessedImage({
    required this.jpeg,
    required this.width,
    required this.height,
  });
}

class ImageProc {
  static const defaultMaxEdge = 1600;
  static const defaultQuality = 80;

  /// [bgra] 为自上而下的 32 位 BGRA 像素。
  static ProcessedImage toJpeg(
    Uint8List bgra,
    int width,
    int height, {
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
  }) {
    var image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bgra.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    final longEdge = width > height ? width : height;
    if (longEdge > maxEdge) {
      final scale = maxEdge / longEdge;
      image = img.copyResize(
        image,
        width: (width * scale).round(),
        height: (height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    final jpeg = img.encodeJpg(image, quality: quality);
    return ProcessedImage(
      jpeg: Uint8List.fromList(jpeg),
      width: image.width,
      height: image.height,
    );
  }

  /// 裁剪（手动框选重试用）：输入归一化矩形（0..1）。
  static ProcessedImage cropToJpeg(
    Uint8List bgra,
    int width,
    int height,
    double x1,
    double y1,
    double x2,
    double y2, {
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
  }) {
    final px1 = (x1.clamp(0, 1) * width).round().clamp(0, width - 1);
    final py1 = (y1.clamp(0, 1) * height).round().clamp(0, height - 1);
    final px2 = (x2.clamp(0, 1) * width).round().clamp(px1 + 1, width);
    final py2 = (y2.clamp(0, 1) * height).round().clamp(py1 + 1, height);
    final w = px2 - px1;
    final h = py2 - py1;
    final src = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bgra.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    final cropped = img.copyCrop(src, x: px1, y: py1, width: w, height: h);
    final longEdge = w > h ? w : h;
    var out = cropped;
    if (longEdge > maxEdge) {
      final scale = maxEdge / longEdge;
      out = img.copyResize(cropped,
          width: (w * scale).round(),
          height: (h * scale).round(),
          interpolation: img.Interpolation.average);
    }
    return ProcessedImage(
      jpeg: Uint8List.fromList(img.encodeJpg(out, quality: quality)),
      width: out.width,
      height: out.height,
    );
  }

  /// 全黑图检测（FLAG_SECURE 场景，SPEC §8）：所有像素都接近黑。
  static bool isAllBlack(
    Uint8List bgra,
    int width,
    int height, {
    int tolerance = 8,
  }) {
    if (width <= 0 || height <= 0 || bgra.length < width * height * 4) {
      return false;
    }
    // 抽样检查即可（全像素过于昂贵）。
    final step = (width * height ~/ 4096).clamp(1, 64);
    var i = 0;
    for (var p = 0; p < width * height; p += step, i++) {
      final o = p * 4;
      if (bgra[o] > tolerance || bgra[o + 1] > tolerance || bgra[o + 2] > tolerance) {
        return false;
      }
    }
    return true;
  }
}
