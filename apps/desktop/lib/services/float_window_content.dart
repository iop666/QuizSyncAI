/// 悬浮窗内容区：**文本为主**的题目排版（M34 第 8 条重写）。
///
/// 历史与取舍：
/// - M32 自己用 `TextPainter` 一行行画题 —— 公式、化学式、表格全退化成纯文本，
///   答案区也没有模块区分；
/// - M33 改成把主界面同一套 `QuestionCard` **离屏渲染成一张位图**
///   （`PipelineOwner + RenderView + RenderRepaintBoundary → toImage`），格式是
///   一致了，但每帧都要跑一整条 widget → 位图管线、还要出/贴一张高图，
///   实测**悬浮窗明显卡顿**（用户 M34 第 8 条）；
/// - M34 回到「TextPainter 直画」，但这次把排版结果**按指纹缓存**
///   （`FloatNode.painter` 挂住排好的 `TextPainter`），每帧只做画布合成，
///   并且给每道题画出**明显的题目轮廓**：圆角卡片 + 题号徽标 + 题型与把握率、
///   命中选项标色、答案块/解析块各有底色条 —— 不卡顿也看得出模块。
///
/// 代价（明确接受）：公式按 LaTeX 源码显示，不再由 `MathText` 渲染成排版公式。
library;

import 'package:flutter/material.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart'
    show HighlightColors, questionTypeLabels;

import 'float_window_view.dart';

/// 排好版的内容：图元在**内容坐标系**里（y 从 0 开始，宽度 = 内容区宽度）。
class FloatContent {
  const FloatContent(this.nodes, this.height);

  final List<FloatNode> nodes;
  final double height;

  bool get isEmpty => nodes.isEmpty || height <= 0;

  /// 释放缓存的文本排版。
  ///
  /// **M35：这里刻意什么都不做。** 原来对每个 `TextPainter` 调 `dispose()`（释放它
  /// 持有的原生 `ui.Paragraph`），但实测「切极简/正常 → 重建内容 → 释放旧 paragraph」
  /// 这条路径会让进程在 `flutter_windows.dll` 里以 `0xC0000005` 崩掉（用户原话
  /// 「点击上面按钮来回点就崩溃」，每次都是点完几秒后）。改成交给 Dart GC：
  /// 对象不再被引用后由 GC 回收，不再由我们在切换的那一刻显式释放引擎的文本对象。
  /// 配合 [FloatContentBuilder] 的**双份缓存**（正常 / 极简各留一份），来回切换
  /// 不会反复重建，内存也是常数级。
  void dispose() {
    // 故意为空，见上面的说明。
  }
}

/// 内容缓存的键：任何一项变了都要重新排版。
class FloatContentKey {
  const FloatContentKey({
    required this.sessionId,
    required this.signature,
    required this.width,
    required this.fontSize,
    required this.minimal,
    required this.paletteId,
    required this.dark,
  });

  final String sessionId;
  final String signature;
  final double width;
  final double fontSize;

  /// 极简模式（只看题目答案）。
  final bool minimal;
  final String paletteId;
  final bool dark;

  @override
  String toString() => [
        sessionId,
        signature,
        width.toStringAsFixed(1),
        fontSize.toStringAsFixed(1),
        minimal,
        paletteId,
        dark,
      ].join('|');
}

/// 极简模式（只看题目答案）。
///
/// - 选项只留命中的那些（选择/多选/判断的答案就标在选项上，于是
///   `computeHighlight` 不会再要求单独一行「答案：」）；
/// - 解析与阅读材料不显示（材料往往比题目还长）；
/// - 徽标警告清掉。
///
/// 答案本来就是空的时候（AI 没识别出答案）**不要**把选项也删光 —— 那样用户
/// 连题都看不懂了，保留全部选项、让卡片显示「未识别出答案」。
Question abstractQuestion(Question q) {
  final matched = q.matchedLabels;
  final keep = matched.isEmpty
      ? q.options
      : q.options.where((o) => matched.contains(o.label)).toList();
  return q.copyWith(
    options: keep,
    analysis: '',
    material: '',
    warnings: const [],
  );
}

/// 极简模式（M42 重写 / M43 成为**默认模式**）：**纯文本面板**，一题一个可拖选的文本块。
///
/// 用户口径（连问三轮）：
/// - 「希望极简模式可以变成可选中字符的形式，便于我的选中与复制」；
/// - 「做文本形式、可选中」——所以这里**不画任何卡片/圆角底/徽标/色块**，
///   只有文字（顶多一个细分割线），也没有任何动画；
/// - 拖选、高亮、复制由 `float_window_selection.dart` 与合成器负责。
///
/// 排版：**一题一个 `TextPainter`**（题号行 + 题干 + 选项 + 答案行合成一个
/// `TextSpan` 树）。一题一个段落是拖选的关键 —— 跨题拖选时按读序把各段拼起来，
/// 字符下标不会在段间错位。
///
/// M43 第 3 条（用户报「答案题号颜色和背景色高度接近，不明显」）：题号用
/// [FloatWindowPalette.accentStrong]、答案用 [FloatWindowPalette.answerStrong]，
/// 两者都保证与窗口底色的对比度 ≥ 4.5:1。
FloatContent layoutMinimalTextContent(
  List<Question> questions, {
  required double width,
  required double fontSize,
  required FloatWindowPalette palette,
}) {
  final nodes = <FloatNode>[];
  final pad = 10.0;
  final innerW = width - pad * 2;
  // M43 第 3 条：面板里**每一种**文字颜色都要与窗口底色拉够对比度
  // （用户原话「答案题号等颜色和背景色高度接近，不明显」——「等」也包括
  // 题型/把握率这类次要文字，实测它在浅色下只有 3.9:1）。
  final metaArgb = ensureContrast(palette.subtext, palette.background);
  final metaStyle = _bodyStyle(fontSize * 0.8, metaArgb, 400);
  final noStyle = _bodyStyle(fontSize * 0.86, metaArgb, 600);
  final stemStyle = _bodyStyle(fontSize, palette.text, 400);
  final optStyle = _bodyStyle(fontSize, palette.text, 400);
  final hitStyle = _bodyStyle(fontSize, palette.text, 600);
  final seqStyle = _bodyStyle(fontSize, palette.accentStrong, 700);

  double y = 0;
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    final highlight = computeHighlight(q);
    final meta = [
      questionTypeLabels[q.type.wire] ?? q.type.wire,
      if (q.confidence > 0) '把握 ${(q.confidence * 100).round()}%',
      if (q.answerGuessed) 'AI 猜测',
    ].join(' · ');
    final answer = answerTextOf(q);
    // 答案色 = 主界面那套**标绿**（AI 没把握时标黄）的契约色。M44 第 4 条：用户要求
    // 「答案颜色改成绿色」—— 不再把它压暗到 4.5:1（浅色下那样几乎看不出绿），
    // 只保留 2.9:1 的地板（与主界面一致），所以正常就是 #16A34A / #4ADE80。
    final ansArgb = highlight.needsReview
        ? ensureContrast(
            HighlightColors.text(palette.dark, uncertain: true).toARGB32(),
            palette.background,
            minRatio: 2.9)
        : palette.answerStrong;
    final ansStyle = _bodyStyle(fontSize, ansArgb, 700);

    final spans = <TextSpan>[
      TextSpan(text: '第 ${q.ordinal + 1} 题', style: seqStyle),
      if (meta.isNotEmpty) TextSpan(text: '  $meta\n', style: metaStyle),
      TextSpan(text: '${q.stem.trim()}\n', style: stemStyle),
    ];
    for (final o in q.options) {
      final hit = highlight.optionLabels.contains(o.label);
      spans.add(TextSpan(
          text: '${o.label}. ${o.text}${hit ? '  ✓' : ''}\n',
          style: hit ? hitStyle : optStyle));
    }
    if (q.incomplete) {
      spans.add(TextSpan(
          text: '（题目不全${q.answerGuessed ? '，答案是 AI 推断的' : ''}）\n', style: metaStyle));
    }
    spans.add(TextSpan(
        text: answer.isEmpty ? '答案：（未识别出答案）' : '答案：$answer',
        style: answer.isEmpty ? noStyle : ansStyle));

    final tp = floatParagraphSpan(
      TextSpan(children: spans),
      maxWidth: innerW,
    );
    // 一题一个图元：没有底、没有边框，只有文字（用户要的就是「文本形式」）。
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(pad, y, innerW, tp.height),
      text: tp.text?.toPlainText(),
      argb: palette.text,
      fontSize: fontSize,
      painter: tp,
      maxLines: 0,
      questionId: q.questionId,
    ));
    y += tp.height + 14;
    // 题与题之间一条细线（不是卡片、不是圆角块）：纯文本里也要看得出分界。
    if (i != questions.length - 1) {
      nodes.add(FloatNode(
        kind: FloatNodeKind.box,
        rect: Rect.fromLTWH(width * 0.25, y - 7, width * 0.5, 1),
        argb: palette.border,
        radius: 0,
      ));
    }
  }

  return FloatContent(nodes, y > 0 ? y - 14 : 0);
}

/// 答案文本（极简面板与「复制识别内容」共用）。
///
/// 选择题的答案是选项号（`choice`），填空/主观题的答案是 `answerText`；
/// 两者都有时优先给 `answerText`（AI 写全了「B。因为…」这类内容）。
String answerTextOf(Question q) {
  final t = (q.answerText ?? '').trim();
  if (t.isNotEmpty) return t;
  if (q.choice.isNotEmpty) return q.choice.join('、');
  final matched = q.matchedLabels;
  return matched.join('、');
}

/// 把**这一次识别的全部内容**排成纯文本（M43 第 2 条：「复制识别内容」）。
///
/// 与面板上的极简排版**故意不同**：这里给的是完整内容（全部选项、解析、阅读材料），
/// 因为用户要的是「能粘到别处去的识别结果」，而不是屏幕上被裁剪过的视图。
/// 纯函数，便于单测；不含任何界面装饰（没有 ✓、没有题号徽标）。
String recognitionTextOf(List<Question> questions) {
  final buf = StringBuffer();
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    if (i > 0) buf.write('\n');
    final type = questionTypeLabels[q.type.wire] ?? q.type.wire;
    final bits = <String>[type];
    if (q.confidence > 0) bits.add('把握 ${(q.confidence * 100).round()}%');
    final no = q.questionNoLabel;
    if (no != null) bits.add('卷面题号 ${q.questionNo!.trim()}');
    if (q.answerGuessed) bits.add('AI 猜测');
    buf.writeln('第 ${q.ordinal + 1} 题  ${bits.join(' · ')}');
    final stem = q.stem.trim();
    if (stem.isNotEmpty) buf.writeln(stem);
    for (final o in q.options) {
      buf.writeln('${o.label}. ${o.text}');
    }
    final answer = answerTextOf(q);
    buf.writeln(answer.isEmpty ? '答案：（未识别出答案）' : '答案：$answer');
    final analysis = q.analysis.trim();
    if (analysis.isNotEmpty) buf.writeln('解析：$analysis');
    final material = q.material.trim();
    if (material.isNotEmpty) buf.writeln('阅读材料：$material');
  }
  return buf.toString().trimRight();
}

/// 题目列表的指纹（内容变了才重新排版）。
///
/// M35：**按题目 id 排序后再拼**。原来按列表顺序拼，数据库每次返回的顺序只要有一点
/// 不同，指纹就变 → 明明同一批题也会重新排版（白建一整套引擎文本对象，切换/轮询时
/// 反复发生）。排序后「内容一样 → 指纹一样」。
String questionsSignature(List<Question> qs) {
  final parts = qs.map((q) {
    final a = q.answerText ?? '';
    return '${q.questionId}:${q.updatedAt}:${q.ordinal}:${q.questionNo}'
        ':${q.type.wire}:${q.stem.length}:${q.stem.hashCode}'
        ':${q.options.map((o) => '${o.label}=${o.text.hashCode}').join(",")}'
        ':${q.choice.join(",")}:${a.length}:${a.hashCode}'
        ':${q.analysis.length}:${q.confidence}:${q.incomplete}'
        ':${q.answerGuessed}:${q.warnings.length}:${q.material.length}';
  }).toList()
    ..sort();
  return parts.join(';');
}

/// 内容层的缓存 + 入口。**同步**：只做文本排版，不出位图（这就是不卡的原因）。
///
/// M35：缓存从 1 份改成 **2 份**（正常 / 极简各留一份）。用户就是「来回点极简」时
/// 崩的 —— 两份都留着，来回切就不用反复重建排版（既不重复创建引擎文本对象，
/// 也不会因为我们显式释放它们而触发那个 `0xC0000005`），顺带切换更快。
class FloatContentBuilder {
  final Map<String, FloatContent> _cache = {};
  String? _lastKey;
  static const int _maxEntries = 2;

  /// 当前缓存的内容（null = 还没有过内容）。
  FloatContent? get cached => _lastKey == null ? null : _cache[_lastKey!];

  /// 排版（或复用缓存）。题目为空时返回空内容（调用方画空状态）。
  FloatContent build({
    required FloatContentKey key,
    required List<Question> questions,
    required FloatWindowPalette palette,
  }) {
    final k = key.toString();
    final hit = _cache[k];
    if (hit != null) {
      _lastKey = k;
      return hit;
    }
    if (questions.isEmpty) {
      _lastKey = k;
      return const FloatContent([], 0);
    }
    final next = key.minimal
        ? layoutMinimalTextContent(
            questions,
            width: key.width,
            fontSize: key.fontSize,
            palette: palette,
          )
        : layoutQuestionContent(
            questions,
            width: key.width,
            fontSize: key.fontSize,
            palette: palette,
            minimal: false,
          );
    _cache[k] = next;
    _lastKey = k;
    // 超出上限就丢掉最旧的（**不 dispose**：见 FloatContent.dispose 的说明），
    // 但绝不丢当前这一份。
    for (final old in _cache.keys.toList()) {
      if (_cache.length <= _maxEntries) break;
      if (old != _lastKey) _cache.remove(old);
    }
    return next;
  }

  void dispose() {
    _cache.clear();
    _lastKey = null;
  }
}

/// 把题目列表排成内容图元（**纯函数**，只依赖入参）。
FloatContent layoutQuestionContent(
  List<Question> questions, {
  required double width,
  required double fontSize,
  required FloatWindowPalette palette,
  bool minimal = false,
}) {
  final nodes = <FloatNode>[];
  final dark = palette.dark;
  final fg = palette.text;
  final secondary = palette.subtext;
  final accent = palette.accent;
  final card = palette.card;
  final border = palette.border;
  final warnText = HighlightColors.warnText(dark).toARGB32();

  double y = 0;
  for (final q in questions) {
    final highlight = computeHighlight(q);
    final uncertain = highlight.needsReview;
    final hlText = HighlightColors.text(dark, uncertain: uncertain).toARGB32();
    final hlBg =
        HighlightColors.background(dark, uncertain: uncertain).toARGB32();
    final incompleteColor = HighlightColors.incomplete(dark).toARGB32();
    final incompleteBg =
        HighlightColors.incompleteBackground(dark).toARGB32();

    final start = nodes.length;
    final cardTop = y;
    const pad = 9.0;
    final innerW = width - pad * 2;
    final x = pad;
    double cy = cardTop + pad;

    /// 加一行（可换行）文本，返回占用的高度。
    double text(
      String s,
      double size,
      int argb,
      int weight, {
      double left = pad,
      double maxW = 0,
      double top = double.nan,
      bool center = false,
    }) {
      final w = maxW > 0 ? maxW : innerW - (left - pad);
      final tp = floatParagraph(
        s,
        _bodyStyle(size, argb, weight),
        maxWidth: w,
        maxLines: 0,
      );
      final ty = top.isNaN ? cy : top;
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(left, ty, w, tp.height),
        text: s,
        fontSize: size,
        argb: argb,
        weight: weight,
        painter: tp,
        maxLines: 0,
        align: center ? TextAlign.center : TextAlign.left,
      ));
      if (top.isNaN) cy += tp.height;
      return tp.height;
    }

    void box(Rect r, int argb, {double radius = 8, int? borderArgb}) {
      nodes.add(FloatNode(
        kind: FloatNodeKind.box,
        rect: r,
        argb: argb,
        radius: radius,
        borderArgb: borderArgb,
      ));
    }

    // ① 题目不全（整张卡片黄框 + 顶部黄条）。
    if (q.incomplete) {
      final msg = q.answerGuessed
          ? '题目不全（选项被截断或缺失），下面的答案是 AI 按题意推断的'
          : '题目不全（题干或选项被截断）';
      final tp = floatParagraph(msg,
          _bodyStyle(fontSize * 0.82, incompleteColor, 600),
          maxWidth: innerW - 18, maxLines: 0);
      final h = tp.height + 14;
      box(Rect.fromLTWH(x, cy, innerW, h), incompleteBg, radius: 6);
      box(Rect.fromLTWH(x, cy, 4, h), incompleteColor, radius: 2);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 12, cy + 7, innerW - 18, tp.height),
        text: msg,
        painter: tp,
        maxLines: 0,
      ));
      cy += h + 8;
    }

    // ② 标题行：序号 + 题号徽标 + 题型 · 把握率。
    final badgeLabel = q.questionNoLabel ?? '第 ${q.ordinal + 1} 题';
    final badgeTp = floatParagraph(badgeLabel,
        _bodyStyle(fontSize * 0.88, 0xFFFFFFFF, 700),
        maxWidth: innerW, maxLines: 1);
    final badgeW = badgeTp.width + 16;
    final badgeH = badgeTp.height + 6;
    final seqTp = floatParagraph('${q.ordinal + 1}',
        _bodyStyle(fontSize * 0.96, accent, 700),
        maxWidth: 40, maxLines: 1);
    final meta = [
      questionTypeLabels[q.type.wire] ?? q.type.wire,
      if (q.confidence > 0) '把握 ${(q.confidence * 100).round()}%',
      if (q.answerGuessed) 'AI 猜测答案',
    ].join(' · ');
    final metaTp = floatParagraph(meta,
        _bodyStyle(fontSize * 0.8, q.answerGuessed ? incompleteColor : secondary,
            500),
        maxWidth: innerW, maxLines: 1);

    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(x, cy + (badgeH - seqTp.height) / 2, seqTp.width,
          seqTp.height),
      text: '${q.ordinal + 1}',
      painter: seqTp,
    ));
    final badgeLeft = x + seqTp.width + 6;
    box(Rect.fromLTWH(badgeLeft, cy, badgeW, badgeH), accent, radius: 999);
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(badgeLeft + 8, cy + 3, badgeW - 16, badgeTp.height),
      text: badgeLabel,
      painter: badgeTp,
      align: TextAlign.center,
    ));
    // 题型与把握率排在徽标右侧；放不下就另起一行。
    final metaLeft = badgeLeft + badgeW + 8;
    if (metaLeft + metaTp.width <= pad + innerW + 0.5) {
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(metaLeft, cy + (badgeH - metaTp.height) / 2,
            metaTp.width, metaTp.height),
        text: meta,
        painter: metaTp,
      ));
      cy += badgeH;
    } else {
      cy += badgeH + 2;
      text(meta, fontSize * 0.8,
          q.answerGuessed ? incompleteColor : secondary, 500,
          maxW: innerW);
    }
    cy += 6;
    box(Rect.fromLTWH(x, cy, innerW, 1), border, radius: 0);
    cy += 8;

    // ③ 题干（LaTeX 按源码显示；文本为主是有意的取舍）。
    text(q.stem, fontSize, fg, 500);
    cy += 8;

    // ④ 阅读材料（极简模式已被 abstractQuestion 清空）。
    if (q.hasMaterial) {
      final lines = q.material
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .length;
      final msg = '阅读材料（$lines 行，请看主窗口）';
      final tp = floatParagraph(msg,
          _bodyStyle(fontSize * 0.82, secondary, 500),
          maxWidth: innerW - 20, maxLines: 0);
      final h = tp.height + 14;
      box(Rect.fromLTWH(x, cy, innerW, h), palette.analysisBg,
          radius: 6, borderArgb: border);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 10, cy + 7, innerW - 20, tp.height),
        text: msg,
        painter: tp,
        maxLines: 0,
      ));
      cy += h + 8;
    }

    // ⑤ 选项（命中项标色；判断题画「对 / 错」两块）。
    if (q.type == QuestionType.judge && q.options.isNotEmpty) {
      const chips = ['对', '错'];
      double cx = x;
      double chipH = 0;
      for (final label in chips) {
        final hit = highlight.optionLabels.contains(label);
        final tp = floatParagraph(label,
            _bodyStyle(fontSize, hit ? hlText : fg, hit ? 700 : 400),
            maxWidth: innerW, maxLines: 1);
        final w = tp.width + 34;
        final h = tp.height + 14;
        chipH = h;
        if (hit) box(Rect.fromLTWH(cx, cy, w, h), hlBg, radius: 8);
        box(Rect.fromLTWH(cx, cy, w, h), 0x00000000,
            radius: 8, borderArgb: hit ? hlText : border);
        nodes.add(FloatNode(
          kind: FloatNodeKind.text,
          rect: Rect.fromLTWH(cx + 17, cy + 7, tp.width, tp.height),
          text: label,
          painter: tp,
        ));
        cx += w + 10;
      }
      cy += chipH + 10;
    } else {
      for (final o in q.options) {
        final hit = highlight.optionLabels.contains(o.label);
        final label = '${o.label}   ${o.text}${hit ? '   ✓' : ''}';
        final tp = floatParagraph(
            label, _bodyStyle(fontSize, hit ? hlText : fg, hit ? 600 : 400),
            maxWidth: innerW - 18, maxLines: 0);
        final h = tp.height + 10;
        if (hit) box(Rect.fromLTWH(x, cy, innerW, h), hlBg, radius: 6);
        box(Rect.fromLTWH(x, cy, 3, h), hit ? hlText : border, radius: 1.5);
        nodes.add(FloatNode(
          kind: FloatNodeKind.text,
          rect: Rect.fromLTWH(x + 10, cy + 5, innerW - 18, tp.height),
          text: label,
          painter: tp,
          maxLines: 0,
        ));
        cy += h + 4;
      }
      if (q.options.isNotEmpty) cy += 4;
    }

    // ⑥ 答案块（填空 / 主观）或「未识别出答案」。
    if (highlight.highlightAnswerText) {
      text('答案${q.answerGuessed ? '（AI 猜测）' : ''}', fontSize * 0.82,
          q.answerGuessed ? incompleteColor : secondary, 700,
          maxW: innerW);
      cy += 4;
      final answerText = q.answerText ?? '';
      final tp = floatParagraph(answerText,
          _bodyStyle(fontSize, hlText, 600),
          maxWidth: innerW - 26, maxLines: 0);
      final h = tp.height + 20;
      box(Rect.fromLTWH(x, cy, innerW, h), hlBg, radius: 8);
      box(Rect.fromLTWH(x, cy, 4, h), hlText, radius: 2);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 14, cy + 10, innerW - 26, tp.height),
        text: answerText,
        painter: tp,
        maxLines: 0,
      ));
      cy += h + 8;
    } else if (highlight.noAnswer) {
      const msg = '未识别出答案';
      final tp = floatParagraph(msg,
          _bodyStyle(fontSize * 0.9, incompleteColor, 600),
          maxWidth: innerW - 24, maxLines: 0);
      final h = tp.height + 16;
      box(Rect.fromLTWH(x, cy, innerW, h), incompleteBg,
          radius: 8, borderArgb: incompleteColor);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 12, cy + 8, innerW - 24, tp.height),
        text: msg,
        painter: tp,
      ));
      cy += h + 8;
    }

    // ⑦ 解析块（极简模式只看题目答案，不画解析）。
    if (!minimal && q.analysis.isNotEmpty) {
      final bodyTp = floatParagraph(q.analysis,
          _bodyStyle(fontSize * 0.92, fg, 400),
          maxWidth: innerW - 24, maxLines: 0);
      final labelTp = floatParagraph('解析',
          _bodyStyle(fontSize * 0.78, secondary, 700),
          maxWidth: innerW, maxLines: 1);
      final h = labelTp.height + 5 + bodyTp.height + 20;
      box(Rect.fromLTWH(x, cy, innerW, h), palette.analysisBg,
          radius: 8, borderArgb: border);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 12, cy + 10, innerW - 24, labelTp.height),
        text: '解析',
        painter: labelTp,
      ));
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 12, cy + 10 + labelTp.height + 5, innerW - 24,
            bodyTp.height),
        text: q.analysis,
        painter: bodyTp,
        maxLines: 0,
      ));
      cy += h + 8;
    }

    // ⑧ AI 告警。
    for (final w in q.warnings) {
      final tp = floatParagraph(w,
          _bodyStyle(fontSize * 0.82, warnText, 500),
          maxWidth: innerW - 14, maxLines: 0);
      final h = tp.height + 8;
      box(Rect.fromLTWH(x, cy, 3, h), HighlightColors.reviewBadge.toARGB32(),
          radius: 1.5);
      nodes.add(FloatNode(
        kind: FloatNodeKind.text,
        rect: Rect.fromLTWH(x + 9, cy + 4, innerW - 14, tp.height),
        text: w,
        painter: tp,
        maxLines: 0,
      ));
      cy += h + 3;
    }

    // ⑨ 题目轮廓（**最显眼的一层**）：整张卡片的白底 + 圆角描边，
    //    插在这道题所有图元**之前**，这样它天然压在文字下面。
    final cardH = cy + pad - cardTop;
    nodes.insert(
      start,
      FloatNode(
        kind: FloatNodeKind.box,
        rect: Rect.fromLTWH(0, cardTop, width, cardH),
        argb: card,
        radius: 10,
        borderArgb: q.incomplete ? incompleteColor : border,
        borderWidth: q.incomplete ? 2 : 1,
      ),
    );
    y = cardTop + cardH + 8;
  }

  final height = y > 0 ? y : 0.0;
  return FloatContent(nodes, height);
}

TextStyle _bodyStyle(double size, int argb, int weight) => TextStyle(
      fontSize: size,
      color: Color(argb),
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      height: 1.5,
      fontFamily: 'MiSans',
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
    );
