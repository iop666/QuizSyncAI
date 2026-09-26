import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 悬浮球位图合成（用户反馈 M16 第 1 条）。
///
/// 单独一个文件、**不依赖 Flutter / win32**：位图几何与配色的对错可以在纯
/// 单测里断言（描边在球内还是球外、颜色有没有加深），不需要真窗口。
/// `services/floating_ball.dart` 只负责把它交给分层窗口。

/// 描边颜色相对状态主色的加深系数（用户反馈 M16 第 1 条「加深一些描边颜色」）。
///
/// 状态主色是给球体本身用的亮色（蓝 `#1D86FC` / 黄 `#FBD705` / 绿 `#1EB945`），
/// 直接拿来描边对比度不够、看不出「有一圈边」。这里按通道线性压暗 28%
/// （只压 RGB，不动 alpha），黄→琥珀、蓝→深蓝、绿→深绿。
const double kBallStrokeDarken = 0.72;

/// 状态主色加深后的描边颜色（ARGB，alpha 保持不变）。
int darkenBallColor(int argb, {double factor = kBallStrokeDarken}) {
  final a = (argb >> 24) & 0xff;
  int scale(int channel) => (channel * factor).round().clamp(0, 255);
  final r = scale((argb >> 16) & 0xff);
  final g = scale((argb >> 8) & 0xff);
  final b = scale(argb & 0xff);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

/// 把球图（已缩放到目标像素）与**向外**的描边合成成一帧。
///
/// 画布边长 = `球边 + strokePx * 2`：左右上下各留 [strokePx] 的余量，环带落在
/// `半径 ∈ [球半径 - insetPx, 球半径 + strokePx]`，向外那一半在球体之外。
///
/// 为什么必须留余量：原来的写法把环带以 `半径 = size/2`（画布边缘）为中心
/// 往里画，环带有半个宽度压在球体上 —— 用户看到的就是「描边向内，把球吃掉了
/// 一圈」（用户反馈 M16 第 1 条）。球本身的大小不变，描边是**长在外面**的。
///
/// [insetPx] 是额外**往球内重叠**的宽度（M17 第 1 条）：球素材不是标准圆形，
/// 球的外缘与环带内缘之间会露出生硬的空隙，向内重叠一点把缝糊上。描边在
/// **球的下面**（先画环带、再把球按 alpha 盖上去），所以球体本身不会被染色，
/// 只有球边缘真正透明的地方才透出这层重叠 —— 这正是「填缝」需要的效果。
///
/// [strokePx] = 0 时返回的就是球本身（没有余量）。
img.Image composeBallFrame({
  required img.Image art,
  int strokePx = 0,
  int strokeColor = 0,
  double strokeOpacity = 1,
  int insetPx = 0,
}) {
  final ballPx = art.width;
  final size = ballPx + strokePx * 2;
  final canvas = img.Image(width: size, height: size, numChannels: 4);

  if (strokePx > 0 && strokeOpacity > 0) {
    final sr = (strokeColor >> 16) & 0xff;
    final sg = (strokeColor >> 8) & 0xff;
    final sb = strokeColor & 0xff;
    final cx = (size - 1) / 2;
    final cy = (size - 1) / 2;
    // 内缘 = 球半径 - 向内重叠（负值兜底成 0：球很小时不许翻到另一侧）。
    final inner = math.max(0.0, ballPx / 2 - insetPx.toDouble());
    final outer = size / 2;
    final mid = (outer + inner) / 2;
    final half = (outer - inner) / 2;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x - cx;
        final dy = y - cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        // 1px 羽化，避免锯齿。
        final coverage = (half + 0.5 - (dist - mid).abs()).clamp(0.0, 1.0);
        if (coverage <= 0) continue;
        final a = (coverage * strokeOpacity * 255).round().clamp(0, 255);
        if (a == 0) continue;
        canvas.setPixelRgba(x, y, sr, sg, sb, a);
      }
    }
  }

  // 球体贴到中心，**按 alpha 覆盖**在环带之上：球的抗锯齿边缘正好落在
  // 「球半径」处、与环带内缘相接，必须混合而不是硬覆盖。
  for (var y = 0; y < ballPx; y++) {
    for (var x = 0; x < ballPx; x++) {
      final p = art.getPixel(x, y);
      final sa = p.a.toInt();
      if (sa == 0) continue;
      final tx = x + strokePx;
      final ty = y + strokePx;
      final d = canvas.getPixel(tx, ty);
      final da = d.a.toInt();
      final na = sa + da * (255 - sa) ~/ 255;
      if (na == 0) continue;
      int blend(int s, int dv) => (s * sa + dv * da * (255 - sa) ~/ 255) ~/ na;
      canvas.setPixelRgba(
        tx,
        ty,
        blend(p.r.toInt(), d.r.toInt()),
        blend(p.g.toInt(), d.g.toInt()),
        blend(p.b.toInt(), d.b.toInt()),
        na,
      );
    }
  }
  return canvas;
}
