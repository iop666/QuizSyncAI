import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quizsync_core/quizsync_core.dart'
    show
        kBallStrokeInset,
        kDefaultBallOpacity,
        kDefaultBallSize,
        kDefaultBallStroke,
        kDefaultBallStrokeOpacity,
        kDefaultBallStrokeWidth;

import 'package:quizsync_desktop/services/ball_paint.dart';
import 'package:quizsync_desktop/services/floating_ball.dart';

/// M16 第 1 条：**描边要向外**（不是向内），并且**颜色要加深**。
///
/// 原来的写法把环带以「画布边缘半径」为中心往里画：环带有半个宽度压在球体上，
/// 球被吃掉一圈，用户看到的就是「描边向内」。现在画布 = 球 + 两侧余量，环带
/// 整圈落在球体之外。这两件事都能在纯单测里断言 —— 不需要真窗口。
void main() {
  /// 一张「实心圆」球图：半径 = 边长/2，模拟真实素材（去白底后的圆形）。
  img.Image solidCircle(int size) {
    final image = img.Image(width: size, height: size, numChannels: 4);
    final c = (size - 1) / 2;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x - c;
        final dy = y - c;
        if (dx * dx + dy * dy <= (size / 2) * (size / 2)) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return image;
  }

  const blue = 0xFF1D86FC;

  test('描边画在球的外面：画布变大，且在球外的像素上有颜色', () {
    final art = solidCircle(40);
    final frame = composeBallFrame(
        art: art, strokePx: 6, strokeColor: darkenBallColor(blue));

    expect(frame.width, 40 + 6 * 2, reason: '画布 = 球 + 两侧描边余量');
    expect(frame.height, frame.width);

    // 球本身没有被放大/位移：中心像素仍是原来的白球。
    expect(frame.getPixel(frame.width ~/ 2, frame.height ~/ 2).r.toInt(), 255);

    // 球外（左边缘中点）是描边色 —— 这就是「向外」。旧实现只画到画布边缘，
    // 这个点在旧实现里是**完全透明**的（球体之外什么都没有）。
    final left = frame.getPixel(0, frame.height ~/ 2);
    expect(left.a.toInt(), greaterThan(0),
        reason: '球外面必须真的有描边像素');
    expect(left.r.toInt(), lessThan(255));
    expect(left.b.toInt(), greaterThan(left.r.toInt()));

    // 环带内缘之外（球自己的边缘像素）仍然是球本身的颜色：球没被描边盖住。
    final ballEdge = frame.getPixel(6, 6 + 20);
    expect(ballEdge.r.toInt(), 255,
        reason: '球体边缘不能被描边染色（旧实现就是在这里吃掉球一圈）');
    expect(ballEdge.a.toInt(), 255);
  });

  test('关掉描边时画布就是球本身（没有余量、球外透明）', () {
    final art = solidCircle(40);
    final frame = composeBallFrame(art: art);
    expect(frame.width, 40);
    expect(frame.getPixel(0, 0).a.toInt(), 0, reason: '球外的角落完全透明');
    expect(frame.getPixel(20, 20).a.toInt(), 255);
  });

  test('描边颜色 = 状态主色加深（三个状态都变深、alpha 不变）', () {
    for (final state in BallState.values) {
      final dark = darkenBallColor(state.mainColor);
      int ch(int argb, int shift) => (argb >> shift) & 0xff;
      expect(ch(dark, 24), ch(state.mainColor, 24), reason: 'alpha 不动');
      for (final shift in [16, 8, 0]) {
        expect(ch(dark, shift), lessThan(ch(state.mainColor, shift)),
            reason: '${state.label} 的每个通道都要变暗');
      }
    }
    // 具体数值钉住：蓝 #1D86FC → #1560B5（每个通道 ×0.72 后四舍五入）。
    expect(darkenBallColor(blue), 0xFF1560B5);
  });

  test('描边透明度 0 = 没有描边（但画布余量保留，几何不变）', () {
    final art = solidCircle(40);
    final frame = composeBallFrame(
        art: art, strokePx: 5, strokeColor: 0xFF000000, strokeOpacity: 0);
    expect(frame.width, 50);
    expect(frame.getPixel(0, 25).a.toInt(), 0);
  });

  // M17 第 1 条：球素材不是标准圆形，球外缘与环带内缘之间会露缝；
  // 描边从球半径**再往内重叠** 2 个逻辑像素把缝糊上（描边在球的下面，
  // 球体本身不被染色）。
  test('向内重叠把「球与描边之间的缝」糊上，且球体本身不被染色', () {
    // 比环带内缘小 3px 的球：模拟非标准圆（边缘往里缩了一点）。
    img.Image smallCircle(int size, int shrink) {
      final image = img.Image(width: size, height: size, numChannels: 4);
      final c = (size - 1) / 2;
      final r = size / 2 - shrink;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x - c;
          final dy = y - c;
          if (dx * dx + dy * dy <= r * r) {
            image.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
      }
      return image;
    }

    const ballPx = 40;
    const strokePx = 6;
    // 缝：球半径 17，环带内缘原本在 20 → x=6+1 处（离中心 19）什么都不画。
    final noInset = composeBallFrame(
        art: smallCircle(ballPx, 3), strokePx: strokePx, strokeColor: 0xFF1D86FC);
    final gap = noInset.getPixel(strokePx + 1, noInset.height ~/ 2);
    expect(gap.a.toInt(), 0, reason: '不重叠时这里就是那道缝');

    final withInset = composeBallFrame(
        art: smallCircle(ballPx, 3),
        strokePx: strokePx,
        strokeColor: 0xFF1D86FC,
        insetPx: 4);
    final filled = withInset.getPixel(strokePx + 1, withInset.height ~/ 2);
    expect(filled.a.toInt(), greaterThan(0), reason: '向内重叠后缝被描边填上');

    // 球体自己那一片仍然是球（描边在下面，不会把球染色）。
    final center = withInset.getPixel(withInset.width ~/ 2, withInset.height ~/ 2);
    expect(center.r.toInt(), 255);
    expect(center.g.toInt(), 255);
    expect(center.b.toInt(), 255);
  });

  test('默认值：球 40 / 描边宽 4 / 不透明 25% / 向内重叠 2', () {
    expect(kDefaultBallSize, 40);
    expect(kDefaultBallOpacity, 0.7);
    expect(kDefaultBallStroke, isTrue);
    expect(kDefaultBallStrokeWidth, 4);
    expect(kDefaultBallStrokeOpacity, 0.25);
    expect(kBallStrokeInset, 2);
  });
}
