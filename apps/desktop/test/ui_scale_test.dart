import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/app.dart';

/// M14 第 1 条（用户反馈：「ui_scale=0.5 时……界面只剩一半，深色下就是那片黑」）。
///
/// 根因：根节点给下来的是**紧约束**（窗口逻辑尺寸），`Transform.scale` 里放一个
/// `SizedBox(虚拟尺寸)` 会被紧约束夹回窗口尺寸，于是界面按窗口尺寸布局、再被缩小到
/// 一半 —— 只画在左上角，右边/下边是一块没有任何 widget 覆盖的区域（引擎清屏色，
/// 深色主题下就是「那片黑」）。修法是外面套一层 `OverflowBox` 撑开虚拟画布。
///
/// 下面用「一个铺满的子块在缩放后的全局矩形」来判断：它必须正好等于窗口大小。
void main() {
  const probeKey = ValueKey('scale-probe');

  /// 在 [windowSize] 的窗口里以 [scale] 渲染，返回：① 子树看到的逻辑尺寸
  /// ② 铺满子块缩放后的全局矩形（= 实际被画出来的区域）。
  Future<({Size layoutSize, Rect painted})> render(
    WidgetTester tester, {
    required Size windowSize,
    required double scale,
  }) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var layoutSize = Size.zero;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          UiScale(scale: scale, child: child ?? const SizedBox.shrink()),
      home: Builder(builder: (context) {
        layoutSize = MediaQuery.sizeOf(context);
        return const ColoredBox(
          color: Color(0xFF00FF00),
          child: SizedBox.expand(key: probeKey),
        );
      }),
    ));
    await tester.pumpAndSettle();
    return (layoutSize: layoutSize, painted: tester.getRect(find.byKey(probeKey)));
  }

  testWidgets('50%：布局用 2 倍虚拟画布，绘制结果必须铺满窗口（不留黑块）', (tester) async {
    final r = await render(tester,
        windowSize: const Size(900, 600), scale: 0.5);
    expect(r.layoutSize, const Size(1800, 1200),
        reason: '缩放后的逻辑画布 = 窗口 / 缩放比');
    expect(r.painted, const Rect.fromLTWH(0, 0, 900, 600),
        reason: '这一条就是「那片黑」：修之前只有 450×300，右下角没有 widget 覆盖');
  });

  testWidgets('200%：布局用一半虚拟画布，绘制结果同样铺满窗口', (tester) async {
    final r = await render(tester,
        windowSize: const Size(900, 600), scale: 2.0);
    expect(r.layoutSize, const Size(450, 300));
    expect(r.painted, const Rect.fromLTWH(0, 0, 900, 600));
  });

  testWidgets('100%：不套任何缩放层，尺寸原样', (tester) async {
    final r = await render(tester,
        windowSize: const Size(900, 600), scale: 1.0);
    expect(r.layoutSize, const Size(900, 600));
    expect(r.painted, const Rect.fromLTWH(0, 0, 900, 600));
  });

  testWidgets('窗口很小时也不溢出（虚拟画布大于窗口是正常的）', (tester) async {
    final r = await render(tester,
        windowSize: const Size(320, 240), scale: 0.5);
    expect(r.painted, const Rect.fromLTWH(0, 0, 320, 240));
    expect(tester.takeException(), isNull, reason: 'OverflowBox 撑开虚拟画布不该报溢出');
  });
}
