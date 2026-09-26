import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show Option, Question, QuestionType;
import 'package:quizsync_desktop/services/float_window_rich.dart';
import 'package:quizsync_desktop/services/float_window_view.dart';

/// 富文本内容渲染（M40）的回归。
///
/// 这轮把内容区从「`TextPainter` 直排（公式显示成 LaTeX 源码）」换成
/// 「主界面同一套 `QuestionCard` 离屏渲染」，公式/化学式/表格与主界面同源。
/// 这里钉住三件事：① 能量出高度；② 真能出图且**有墨**（不是一张空白）；
/// ③ 按片栅格化：不同片的像素不同、且片高与请求一致。
void main() {
  final palette = FloatWindowPalette.of(dark: false, paletteId: 'white');

  Question q(String stem, {String analysis = ''}) => Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        questionNo: '12',
        stem: stem,
        type: QuestionType.single,
        options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
        choice: const ['A'],
        analysis: analysis,
        confidence: 0.9,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'windows-local',
      );

  FloatRichSpec spec(List<Question> qs, {double fontSize = 13}) => FloatRichSpec(
        questions: qs,
        width: 300,
        fontSize: fontSize,
        fontWeight: 400,
        minimal: false,
        accent: palette.accent,
        dark: false,
        emptyText: '还没有识别记录',
        failed: false,
      );

  int inkCount(Uint8List bgra) {
    var n = 0;
    for (var i = 0; i + 3 < bgra.length; i += 4) {
      if (bgra[i + 3] == 0) continue;
      // 近似白＝底色；明显偏离才算墨迹。
      final b = bgra[i], g = bgra[i + 1], r = bgra[i + 2];
      if ((255 - r).abs() + (255 - g).abs() + (255 - b).abs() > 60) n++;
    }
    return n;
  }

  testWidgets('⑯ M40：富文本内容能量高度、能出图、公式题也有墨', (tester) async {
    final formula = q(r'化简：$\frac{a^2-b^2}{a+b}$ 的结果是？',
        analysis: r'原式 $=\frac{(a+b)(a-b)}{a+b}=a-b$。');
    final h = await tester.runAsync(() => measureRichContentHeight(spec([formula])));
    expect(h, isNotNull);
    expect(h! > 40, isTrue, reason: '一张题目卡片至少几十逻辑像素高，量出 $h');

    final tile = await tester.runAsync(() => rasterRichTile(spec([formula]),
        tileTop: 0, tileHeight: 300, devicePixelRatio: 1, backgroundArgb: 0xFFFFFFFF));
    expect(tile, isNotNull);
    expect(tile!.length, 300 * 300 * 4, reason: '位图长度 = 宽 × 片高 × 4');
    expect(inkCount(tile), greaterThan(200),
        reason: '公式/题干/选项都要画出来，不该是一张白图');
  });

  testWidgets('⑰ M40：按片栅格化——不同片的像素不同、片高就是请求的高度', (tester) async {
    final qs = [q(r'第一题：$x^2+1$', analysis: '解析一'), q(r'第二题：$y=mx+b$')];
    final s = spec(qs);
    final total = await tester.runAsync(() => measureRichContentHeight(s));
    expect(total! > 320, isTrue, reason: '两题应当高过一片，才谈得上分片');

    final t0 = await tester.runAsync(() => rasterRichTile(s,
        tileTop: 0, tileHeight: 160, devicePixelRatio: 1, backgroundArgb: 0xFFFFFFFF));
    final t1 = await tester.runAsync(() => rasterRichTile(s,
        tileTop: 160, tileHeight: 160, devicePixelRatio: 1, backgroundArgb: 0xFFFFFFFF));
    expect(t0!.length, 160 * 300 * 4);
    expect(t1!.length, 160 * 300 * 4);
    var same = 0;
    for (var i = 0; i < t0.length; i++) {
      if (t0[i] != t1[i]) same++;
    }
    expect(same, greaterThan(500), reason: '两片内容不同（错位/空白说明切片没生效）');
    expect(inkCount(t0) > 100 && inkCount(t1) > 100, isTrue,
        reason: '两片都该有墨（题干/解析）');
  });

  testWidgets('⑱ M40：极简模式与 DPR 都进指纹（缓存不会串）', (tester) async {
    final s1 = spec([q(r'题目 $x^2$')]);
    final s2 = FloatRichSpec(
      questions: s1.questions,
      width: s1.width,
      fontSize: s1.fontSize,
      fontWeight: s1.fontWeight,
      minimal: true,
      accent: s1.accent,
      dark: s1.dark,
      emptyText: s1.emptyText,
      failed: false,
    );
    expect(s1.key, isNot(s2.key));
    expect(s1.contentSignature, isNot(s2.contentSignature));
    // DPR/尺寸变了，栅格化出来的位图尺寸跟着变（出图时由 (width, dpr) 决定）。
    final a = await tester.runAsync(() => rasterRichTile(s1,
        tileTop: 0, tileHeight: 100, devicePixelRatio: 1, backgroundArgb: 0xFFFFFFFF));
    final b = await tester.runAsync(() => rasterRichTile(s1,
        tileTop: 0, tileHeight: 100, devicePixelRatio: 2, backgroundArgb: 0xFFFFFFFF));
    expect(a!.length, 100 * 300 * 4);
    expect(b!.length, 200 * 600 * 4);
  });
}
