import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show kFloatWindowAspects, kFloatWindowPalettes, floatWindowPaletteOf;
import 'package:quizsync_desktop/services/float_window_view.dart';

/// 悬浮窗外壳层（M33 / M34）的回归：
/// ① 顶部第一栏：一排**图标**按钮（下一条在最右、然后是上一条 / 重新识别 /
///    极简 / 锁定），**没有**字号按钮，也**不再**显示「共 N 题 / N 张图片」；
/// ② 只有顶部第一栏是拖拽区；
/// ③ 悬停时出提示气泡（只认顶部按钮）；
/// ④ 识别中：提示贴在内容区**下部**，底部按钮照旧可点；
/// ⑤ 命中区与画出来的按钮一致；
/// ⑥ 三种外观的比例与默认竖屏；
/// ⑦ 配色默认浅色系、6 套都在，**纯净白真的是中性白**（M34 第 6 条）；
/// ⑧ 渲染输出预乘 BGRA、四角透明、透明度作用在 alpha 上；
/// ⑨ 底部按钮：尺寸适度、纯色整条、不做 Dock 式放大（用户否掉了 Dock 那一版）。
void main() {
  /// 竖屏 9:20 是默认外观。
  final portrait = kFloatWindowAspects.first;
  const w = 342.0;
  final h = 342 / (9 / 20);

  FloatWindowModel model({
    bool busy = false,
    bool minimal = false,
    bool multiPage = false,
    int staged = 0,
    int limit = 6,
    int total = 3,
    int index = 0,
    double scrollPx = 0,
    List<FloatNode> content = const [],
    double contentHeight = 0,
    String? hoveredId,
    String paletteId = 'white',
    String? tipText,
  }) =>
      FloatWindowModel(
        palette: FloatWindowPalette.of(dark: false, paletteId: paletteId),
        index: index,
        total: total,
        createdAt: DateTime(2026, 9, 21, 14, 3).millisecondsSinceEpoch,
        busy: busy,
        minimal: minimal,
        multiPage: multiPage,
        stagedCount: staged,
        multiPageLimit: limit,
        scrollPx: scrollPx,
        content: content,
        contentHeight: contentHeight,
        hoveredId: hoveredId,
        tipText: tipText,
      );

  FloatFrame layout(FloatWindowModel m, {double width = w, double? height}) =>
      layoutFloatWindow(m, width: width, height: height ?? h);

  List<String> textsOf(FloatFrame f) =>
      [for (final n in f.nodes) if (n.text != null) n.text!];

  testWidgets('① 顶部一排图标按钮（无字号按钮），标题栏不再有题数/图片数', (tester) async {
    final frame = layout(model(index: 1, total: 3));
    final ids = frame.hitRegions.keys.toSet();
    for (final id in [
      FloatAction.next,
      FloatAction.prev,
      FloatAction.regenerate,
      FloatAction.toggleMinimal,
      FloatAction.toggleLock,
      FloatAction.capture,
      FloatAction.multiPage,
    ]) {
      expect(ids, contains(id), reason: '缺少按钮 $id');
    }
    // 按钮是**图标**：文字节点里应当是图标字形（码点），而不是中文标签。
    final iconNodes = frame.nodes
        .where((n) => n.fontFamily != null && n.text != null)
        .toList();
    expect(iconNodes.length, greaterThanOrEqualTo(5), reason: '顶部是一排图标按钮');
    expect(iconNodes.first.fontFamily, Icons.chevron_right.fontFamily);
    // 图标也要在按钮里**垂直居中**（否则字形贴上沿，看着像按钮坏了）。
    final firstBtn = frame.nodes.firstWhere((n) => n.id == FloatAction.next);
    expect(iconNodes.first.rect.center.dy,
        closeTo(firstBtn.rect.center.dy, 0.5),
        reason: '图标要居中');
    // 顶部按钮的 id 集合与 `kFloatHeaderActions` 一致（悬停重画只认这一组）。
    final headerIds = {
      for (final n in frame.nodes)
        if (n.id != null && n.rect.top < frame.headerRect.bottom) n.id!,
    };
    expect(headerIds, kFloatHeaderActions);
    expect(kFloatHeaderActions, isNot(contains(FloatAction.capture)));
    // 底部两个按钮是**带文字**的整条按钮（不是图标块）。
    expect(textsOf(frame), contains('识别一张'));
    expect(textsOf(frame), contains('多页识别'));
    // 最新的那条：下一条不可点（但仍画出来）。
    final latest = layout(model(index: 0, total: 3));
    expect(latest.hitRegions.keys, isNot(contains(FloatAction.next)));
    expect(latest.nodes.any((n) => n.id == FloatAction.next), isTrue);
    // 顶部第一栏的文字信息：只有识别序号与时间。
    final texts = textsOf(frame);
    expect(texts, contains('第 2/3 次识别'));
    expect(texts, contains('2026-09-21 14:03'));
    expect(texts.any((t) => t.contains('共 ')), isFalse, reason: '删掉「共 N 题」');
    expect(texts.any((t) => t.contains('张图片')), isFalse, reason: '删掉「N 张图片」');
    // 所有图元都在窗口内。
    for (final n in frame.nodes) {
      expect(n.rect.left, greaterThanOrEqualTo(-0.5));
      expect(n.rect.top, greaterThanOrEqualTo(-0.5));
      expect(n.rect.right, lessThanOrEqualTo(w + 0.5), reason: '${n.id} 越右边界');
      expect(n.rect.bottom, lessThanOrEqualTo(h + 0.5), reason: '${n.id} 越下边界');
    }
  });

  testWidgets('①b 下一条在上一条右边（M34 第 3 条：两者互换）', (tester) async {
    final frame = layout(model(index: 1, total: 3));
    final next = frame.hitRegions[FloatAction.next]!;
    final prev = frame.hitRegions[FloatAction.prev]!;
    expect(next.left, greaterThan(prev.left), reason: '下一条应当在上一条右侧');
    expect(next.center.dy, closeTo(prev.center.dy, 0.01), reason: '同一排');
  });

  testWidgets('② 只有顶部第一栏是拖拽区', (tester) async {
    final frame = layout(model());
    expect(frame.headerRect.top, 0);
    expect(frame.headerRect.width, w);
    // 第一栏高度明显小于整窗，且不覆盖内容区。
    expect(frame.headerRect.height, lessThan(h * 0.4));
    expect(frame.headerRect.bottom, lessThanOrEqualTo(frame.bodyRect.top + 0.5));
  });

  testWidgets('③ 悬停出提示气泡（顶部图标按钮）', (tester) async {
    final plain = layout(model());
    expect(textsOf(plain), isNot(contains('上一条')));

    final hovered = layout(model(index: 1, total: 3, hoveredId: FloatAction.prev));
    expect(textsOf(hovered), contains('上一条'), reason: '悬停要显示提示文字');
    final bubbles = hovered.nodes
        .where((n) => n.text == '上一条' && n.fontFamily == null)
        .toList();
    expect(bubbles.length, 1);
    expect(bubbles.single.rect.top,
        greaterThan(hovered.hitRegions[FloatAction.prev]!.bottom - 1));
  });

  testWidgets('④ 识别中：提示在内容区下部，Dock 栏照旧可点', (tester) async {
    final frame = layout(model(busy: true, contentHeight: 400));
    final banner = frame.nodes.lastWhere((n) => n.text == '识别进行中…');
    expect(banner.rect.center.dy,
        greaterThan(frame.bodyRect.center.dy + frame.bodyRect.height * 0.15),
        reason: '识别中提示要贴在内容区下部，不能在中间');
    expect(banner.rect.bottom, lessThanOrEqualTo(frame.bodyRect.bottom + 0.5));
    expect(frame.hitRegions.keys, contains(FloatAction.capture));
    expect(frame.hitRegions.keys, contains(FloatAction.multiPage));
    expect(textsOf(frame), isNot(contains('取消识别')));
    // Dock 有标签（Dock 栏风格：图标 + 名称）。
    expect(textsOf(frame), contains('识别一张'));
    expect(textsOf(frame), contains('多页识别'));
  });

  testWidgets('⑤ 命中区与画出来的按钮是同一份数据', (tester) async {
    final frame = layout(model(index: 1, total: 3));
    final clickable = {
      for (final n in frame.nodes)
        if (n.clickable) n.id!: n,
    };
    expect(frame.hitRegions.keys.toSet(), clickable.keys.toSet());
    for (final e in frame.hitRegions.entries) {
      expect(e.value, clickable[e.key]!.rect);
    }
    // 底部按钮的命中区就是整条按钮本身（不再有「画放大、点原槽位」那种错位）。
    final footer = clickable[FloatAction.capture]!;
    expect(frame.hitRegions[FloatAction.capture], footer.rect);
  });

  testWidgets('⑥ 三种外观 + 默认竖屏 9:20', (tester) async {
    expect(kFloatWindowAspects.length, 3, reason: '只保留三种外观');
    expect(kFloatWindowAspects.first.id, 'portrait');
    final landscape = kFloatWindowAspects.last;
    expect(landscape.ratio, greaterThan(1));
    expect(kFloatWindowAspects[1].ratio, lessThan(kFloatWindowAspects[0].ratio));
    expect(portrait.heightAt(1), greaterThan(portrait.widthAt(1)));
    expect(landscape.heightAt(1), lessThan(landscape.widthAt(1)));
    for (final a in kFloatWindowAspects) {
      expect(a.widthAt(1), lessThan(1600));
      expect(a.heightAt(1), lessThan(1000));
    }
  });

  testWidgets('⑦ 配色：6 套浅色系；纯净白是中性白，不再套薄荷绿（第 6 条）', (tester) async {
    for (final spec in kFloatWindowPalettes) {
      final p = FloatWindowPalette.of(dark: false, paletteId: spec.id);
      expect(_luma(p.background), greaterThan(215),
          reason: '${spec.label} 在明亮模式下应当是浅色底');
      expect(p.dark, isFalse);
    }
    expect(floatWindowPaletteOf(null).id, 'white');
    expect(kFloatWindowPalettes.length, 6);

    // 纯净白：底色三个通道基本相等 = 中性，且与薄荷绿明显不是一个色。
    final white = FloatWindowPalette.of(dark: false, paletteId: 'white');
    final mint = FloatWindowPalette.of(dark: false, paletteId: 'mint');
    expect(_channelSpread(white.background), lessThanOrEqualTo(4),
        reason: '纯净白的底色必须是中性的（M33 这里错填了绿色种子）');
    expect(_channelSpread(white.header), lessThanOrEqualTo(6));
    expect(white.accent, isNot(mint.accent));
    expect(mint.accent, isNot(white.accent));

    // 深色由「明暗模式」负责：同一个配色在深色模式下底色变暗。
    final darkWhite = FloatWindowPalette.of(dark: true, paletteId: 'white');
    expect(_luma(darkWhite.background), lessThan(_luma(white.background)));
    expect(darkWhite.dark, isTrue);
    // 配色缓存：同一 key 返回同一个对象（避免每帧重造）。
    expect(identical(white, FloatWindowPalette.of(dark: false, paletteId: 'white')),
        isTrue);
  });

  testWidgets('⑧ 分块出图：一块图元 → 一张位图（预乘 BGRA，可指定原点与底色）', (tester) async {
    final frame = layout(model(contentHeight: 400));
    final chrome = frame.nodes
        .where((n) => !n.inBody && !n.overlay)
        .toList(growable: false);
    final pw = w.round();
    final ph = h.round();
    // `Picture.toImage` 依赖真实事件循环：flutter_test 的假异步环境里必须走
    // `tester.runAsync`，否则这个 Future 永远不会完成（实测会卡住整个测试）。
    final full = (await tester.runAsync(() => renderNodes(
          chrome,
          width: w,
          height: h,
          devicePixelRatio: 1,
          backgroundArgb: 0xFFFFFFFF,
        )))!;
    expect(full.length, pw * ph * 4);
    expect(full[3], 255, reason: '铺了不透明底就该是不透明的');
    final center = ((ph ~/ 2) * pw + pw ~/ 2) * 4;
    expect(full[center + 3], 255);
    // 预乘不变式：每个通道都不超过 alpha。
    for (var i = 0; i < full.length; i += 4 * 97) {
      expect(full[i], lessThanOrEqualTo(full[i + 3]));
      expect(full[i + 1], lessThanOrEqualTo(full[i + 3]));
      expect(full[i + 2], lessThanOrEqualTo(full[i + 3]));
    }
    // 通道序 = BGRA（`UpdateLayeredWindow` 要的）：取内容区顶部那个点应等于窗口底色。
    final bg = FloatWindowPalette.of(dark: false, paletteId: 'white').background;
    final probe = (((frame.headerRect.bottom + 4).round()) * pw + pw ~/ 2) * 4;
    expect(full[probe], bg & 0xFF, reason: 'B 通道');
    expect(full[probe + 1], (bg >> 8) & 0xFF, reason: 'G 通道');
    expect(full[probe + 2], (bg >> 16) & 0xFF, reason: 'R 通道');

    // 不铺底 = 透明图（浮层用），且尺寸由 width/height 决定（内容是「一块」而不是整窗）。
    final piece = (await tester.runAsync(() => renderNodes(
          frame.nodes.where((n) => n.inBody).toList(growable: false),
          width: frame.bodyRect.width,
          height: 120,
          devicePixelRatio: 1,
        )))!;
    expect(piece.length, frame.bodyRect.width.round() * 120 * 4);
    expect(piece[3], 0, reason: '没铺底时角落应当是透明的');
  });

  testWidgets('⑨ 底部按钮：尺寸适度、纯色整条、不做 Dock 式放大', (tester) async {
    final plain = layout(model());
    final palette = FloatWindowPalette.of(dark: false, paletteId: 'white');
    final btn = plain.nodes.firstWhere((n) => n.id == FloatAction.capture);
    // 适度：一行文字那么高，不是大块头（用户明确「按钮不要太大」）。
    expect(btn.rect.height, greaterThanOrEqualTo(18));
    expect(btn.rect.height, lessThanOrEqualTo(34));
    expect(btn.rect.width, greaterThan(btn.rect.height * 2), reason: '整条按钮');
    expect(btn.argb, palette.accent, reason: '纯色实心按钮');
    expect(btn.borderArgb, isNull);
    // 文字必须**垂直居中**（用户反馈「按钮文字异常」就是它贴了上沿）。
    final label = plain.nodes.firstWhere((n) => n.text == '识别一张');
    expect(label.rect.center.dy, closeTo(btn.rect.center.dy, 0.5),
        reason: '按钮文字要居中，不能贴在上沿');
    expect(label.rect.center.dx, closeTo(btn.rect.center.dx, 0.5));
    // 按钮上下留白都存在（不会贴到窗口底边）。
    expect(btn.rect.bottom, lessThan(plain.height - 4));
    expect(plain.height - btn.rect.bottom, lessThan(20));
    expect(plain.bodyRect.bottom, lessThanOrEqualTo(btn.rect.top + 0.5));

    // 悬停底部按钮**什么都不该变**（Dock 放大那一版已经被否掉）。
    final hovered = layout(model(hoveredId: FloatAction.capture));
    expect(hovered.hitRegions[FloatAction.capture], plain.hitRegions[FloatAction.capture]);
    expect(hovered.nodes.firstWhere((n) => n.id == FloatAction.capture).rect,
        btn.rect);
    expect(textsOf(hovered).where((t) => t == '识别一张').length, 1,
        reason: '底部按钮不该因为悬停多出一个提示气泡');

    // 多页模式：三个按钮，取消多页也在；文字随状态变。
    final multi = layout(model(multiPage: true, staged: 2));
    expect(multi.hitRegions.keys, contains(FloatAction.finishMulti));
    expect(multi.hitRegions.keys, contains(FloatAction.addPage));
    expect(multi.hitRegions.keys, contains(FloatAction.cancelMulti));
    expect(textsOf(multi), contains('继续添加页（2/6）'));
    expect(textsOf(multi), contains('取消多页'));
  });

  testWidgets('⑩ 内容图元被平移进内容区并标记为 inBody（滚动裁切用）', (tester) async {
    final content = [
      FloatNode(
        kind: FloatNodeKind.box,
        rect: const Rect.fromLTWH(0, 0, 300, 40),
        argb: 0xFFFFFFFF,
      ),
    ];
    final frame = layout(model(content: content, contentHeight: 2000));
    final body = frame.nodes.last;
    expect(body.inBody, isTrue);
    expect(body.rect.left, closeTo(frame.bodyRect.left, 0.01));
    expect(body.rect.top, closeTo(frame.bodyRect.top, 0.01));
    expect(frame.scrollMax,
        closeTo(2000 - frame.bodyRect.height, 0.01));
    // 内容不高时不能滚。
    expect(layout(model(content: content, contentHeight: 40)).scrollMax, 0);
  });

  testWidgets('⑪ M43：「复制识别内容」只在默认模式出现，且排在三个按钮的最后', (tester) async {
    final detail = layout(model());
    expect(detail.hitRegions.keys, isNot(contains(FloatAction.copyContent)),
        reason: '详细解析模式不加这个按钮');
    expect(textsOf(detail), isNot(contains('复制识别内容')));

    final mini = layout(model(minimal: true));
    expect(mini.hitRegions.keys, contains(FloatAction.copyContent));
    expect(textsOf(mini), contains('复制识别内容'));
    // 用户口径（M43 第 2 条）：复制按钮排在**三个按钮的最后一个**。
    final copy = mini.hitRegions[FloatAction.copyContent]!;
    expect(copy.left, greaterThan(mini.hitRegions[FloatAction.multiPage]!.left),
        reason: '复制按钮必须在「多页识别」右边（= 三个里的最后一个）');
    expect(copy.right, closeTo(w - 8, 0.01),
        reason: '最后一个按钮贴右边界（底部一行按顺序左→右排）');
    // 默认模式下底部是三个按钮：识别一张 / 多页识别 / 复制识别内容。
    expect(mini.hitRegions.keys, contains(FloatAction.capture));
    expect(mini.hitRegions.keys, contains(FloatAction.multiPage));
    final rects = [
      mini.hitRegions[FloatAction.capture]!,
      mini.hitRegions[FloatAction.multiPage]!,
      copy,
    ];
    for (final r in rects) {
      expect(r.left, greaterThanOrEqualTo(-0.5));
      expect(r.right, lessThanOrEqualTo(w + 0.5));
    }
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse, reason: '按钮不能重叠');
      }
    }
  });

  testWidgets('⑫ M42：一次性提示（已复制…）画在浮层里、在内容区下部', (tester) async {
    final frame = layout(model(minimal: true, tipText: '已复制本次识别内容（2 题）'));
    final tip = frame.nodes.firstWhere((n) => n.text == '已复制本次识别内容（2 题）');
    expect(tip.overlay, isTrue, reason: '提示是浮层，单独出图');
    expect(tip.rect.bottom, lessThanOrEqualTo(frame.bodyRect.bottom + 0.5));
    expect(tip.rect.top, greaterThan(frame.bodyRect.top));
    // 不显示时不该有这条图元。
    expect(textsOf(layout(model(minimal: true))),
        isNot(contains('已复制本次识别内容（2 题）')));
  });

  testWidgets('⑬ M43：两个模式的按钮提示写明「默认模式 / 详细解析模式」', (tester) async {
    // 悬停才画提示气泡，气泡文字就是模式名（M43 第 1 条：极简模式 = 默认模式）。
    final hoverMini =
        layout(model(minimal: true, hoveredId: FloatAction.toggleMinimal));
    expect(textsOf(hoverMini).join('\n'), contains('详细解析模式'));
    final hoverDetail =
        layout(model(minimal: false, hoveredId: FloatAction.toggleMinimal));
    expect(textsOf(hoverDetail).join('\n'), contains('默认模式'));
  });
}

/// 感知亮度（0–255），只用来判断「浅 / 深」。
double _luma(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/// 三个通道的最大差（0 = 完全中性灰）。
int _channelSpread(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final maxV = [r, g, b].reduce((a, c) => a > c ? a : c);
  final minV = [r, g, b].reduce((a, c) => a < c ? a : c);
  return maxV - minV;
}
