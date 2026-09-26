import 'package:flutter/material.dart';

import 'package:quizsync_core/quizsync_core.dart';

import 'app_theme.dart';
import 'math_text.dart';
import 'theme_colors.dart';
import 'widgets.dart';

/// SPEC 4.3：选项行 / 答案区块的标绿渲染。
/// 颜色与 ✓ 图标严格按契约；✓ 是刻意加的（颜色不能是唯一信息通道）。
///
/// M8 界面优化：题干/选项/解析的层级、间距、徽标统一走共享设计基线；
/// **标绿配色与 `option-*` / `answer-block` / `review-badge` 这些键保持不变**。
class QuestionCard extends StatelessWidget {
  final Question question;
  final double fontSize;

  /// 题目正文的字重（wght，用户反馈 1：Windows 端可调）。
  /// null = 保持原样（题干 w500，其余继承外部样式）——安卓端不传这个参数。
  final int? fontWeight;

  /// 是否**总是**显示「把握 N%」（默认只在 0 < confidence < 1 时显示）。
  ///
  /// Windows 悬浮窗传 true（M33 第 13 条：题号后面要跟上题型与 AI 把握率）：
  /// 那个窗里没有别的置信度线索，缺了它用户不知道这条答案有多可信。
  final bool alwaysShowConfidence;

  const QuestionCard({
    super.key,
    required this.question,
    required this.fontSize,
    this.fontWeight,
    this.alwaysShowConfidence = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final highlight = computeHighlight(question);
    final fg = dark ? Colors.grey[100]! : const Color(0xFF1F2426);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final weight = fontWeight;
    // 用户反馈 13：AI 没把握时，命中的选项/答案区用黄色而不是绿色。
    final uncertain = highlight.needsReview;

    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      // 用户需求 2：题目不全 → 整个题目外框标黄。
      shape: question.incomplete
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(
                  color: HighlightColors.incomplete(dark), width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (question.incomplete) ...[
              _incompleteBanner(dark),
              const SizedBox(height: AppSpacing.sm),
            ],
            _header(context, dark, secondary),
            const SizedBox(height: AppSpacing.md),
            // 阅读材料（用户反馈 15）：阅读类题目的文章原文，**默认折叠**，
            // 点击展开；放在题干之前（材料在题目原文里本来也在前面）。
            if (question.hasMaterial) ...[
              _MaterialPanel(
                material: question.material,
                dark: dark,
                fontSize: fontSize,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            // 题干：LaTeX 经 MathText 渲染，失败回退等宽源码。
            MathText(
              key: const ValueKey('question-stem'),
              text: question.stem,
              style: weight == null
                  ? TextStyle(
                      fontSize: fontSize,
                      height: 1.6,
                      color: fg,
                      fontWeight: FontWeight.w500)
                  : questionWeightStyle(weight,
                      base: TextStyle(
                          fontSize: fontSize, height: 1.6, color: fg)),
            ),
            if (question.options.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ..._optionRows(dark),
            ],
            if (highlight.highlightAnswerText) ...[
              const SizedBox(height: AppSpacing.md),
              ..._answerBlock(dark, uncertain),
            ],
            if (highlight.noAnswer) ...[
              const SizedBox(height: AppSpacing.md),
              _noAnswerHint(dark),
            ],
            if (question.analysis.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _analysisBlock(dark, secondary, fg),
            ],
            if (question.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _warnings(dark),
            ],
            if (question.answerEdited || question.analysisEdited) ...[
              const SizedBox(height: AppSpacing.sm),
              StatusPill(
                label: '已人工修改',
                color: theme.colorScheme.primary,
                icon: Icons.edit_outlined,
                filled: false,
              ),
            ],
          ],
        ),
      ),
    );

    // 选项行 / 答案区 / 解析里的文字样式都没写 fontWeight，会从这里继承，
    // 所以只要在最外层包一层就能让整个题目的正文跟着字重设置走。
    return weight == null
        ? card
        : DefaultTextStyle.merge(
            style: questionWeightStyle(weight), child: card);
  }

  /// 题目不全的顶部横幅（用户需求 2）。
  Widget _incompleteBanner(bool dark) {
    final color = HighlightColors.incomplete(dark);
    return Container(
      key: const ValueKey('incomplete-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: HighlightColors.incompleteBackground(dark),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.report_gmailerrorred_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              question.answerGuessed
                  ? '题目不全（选项被截断或缺失），下面的答案是 AI 按题意推断的'
                  : '题目不全（题干或选项被截断）',
              style: TextStyle(
                  fontSize: fontSize * 0.82,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool dark, Color secondary) {
    final theme = Theme.of(context);
    final q = question;
    final highlight = computeHighlight(q);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        // 排序序号放在题号徽标**外面、前面**（用户反馈 7）：
        // 序号是我们给的（本次识别的第几题），题号是 AI 从图里读到的，
        // 两者含义不同，挤在同一个徽标里会被读成同一个数字。
        //
        // M33：**序号后面不带点号**（用户原话「题号不带 `1.`，说的只是 `.`，
        // 不是不显示」）—— 序号照旧显示，只是把 `1.` 写成 `1`。
        Text(
          '${q.ordinal + 1}',
          key: const ValueKey('question-seq'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        // 题号徽标（最醒目的锚点）：识别到的题号；没识别到就用序号兜底。
        Container(
          key: const ValueKey('question-title'),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            q.questionNoLabel ?? '第 ${q.ordinal + 1} 题',
            style: const TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ),
        StatusPill(
          label: questionTypeLabels[q.type.wire] ?? q.type.wire,
          color: secondary,
          filled: false,
        ),
        // AI 猜测答案徽标（用户需求 2）。
        if (q.answerGuessed)
          Container(
            key: const ValueKey('answer-guess-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: HighlightColors.incompleteBackground(dark),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: HighlightColors.incomplete(dark)),
            ),
            child: Text('AI 猜测答案',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: HighlightColors.incomplete(dark))),
          ),
        // 置信度徽标（ai-contract §6）。
        if (highlight.needsReview)
          Container(
            key: const ValueKey('review-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: HighlightColors.reviewBadgeBackground,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: HighlightColors.reviewBadge),
            ),
            child: const Text('AI 不确定，建议复核',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: HighlightColors.reviewBadge)),
          ),
        if (q.answerInImage)
          StatusPill(
            label: '图中已印答案',
            color: secondary,
            icon: Icons.image_outlined,
            filled: false,
          ),
        // 置信度徽标（ai-contract §6）；悬浮窗要求**总是**显示把握率（M33 第 13 条）。
        if (q.confidence > 0 && (alwaysShowConfidence || q.confidence < 1))
          Text(
            '把握 ${(q.confidence * 100).round()}%',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
        Text(_sourceAndTime(), style: TextStyle(fontSize: 11, color: secondary)),
      ],
    );
  }

  String _sourceAndTime() {
    final t = DateTime.fromMillisecondsSinceEpoch(question.updatedAt);
    return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  List<Widget> _optionRows(bool dark) {
    final highlight = computeHighlight(question);
    final fg = dark ? Colors.grey[100]! : const Color(0xFF1F2426);
    // 用户反馈 13：不确定 → 命中项用黄色。
    final uncertain = highlight.needsReview;

    if (question.type == QuestionType.judge) {
      // 判断题：固定「对 / 错」两个按钮（ai-contract §5）。
      return [
        Row(
          children: [
            _judgeButton('对', dark, uncertain),
            const SizedBox(width: AppSpacing.md),
            _judgeButton('错', dark, uncertain),
          ],
        ),
      ];
    }

    return [
      for (final opt in question.options)
        _optionRow(
          key: 'option-${opt.label}',
          label: opt.label,
          text: opt.text,
          highlighted: highlight.optionLabels.contains(opt.label),
          dark: dark,
          fg: fg,
          uncertain: uncertain,
        ),
    ];
  }

  Widget _judgeButton(String label, bool dark, bool uncertain) {
    final highlighted = computeHighlight(question).optionLabels.contains(label);
    final color = HighlightColors.text(dark, uncertain: uncertain);
    return Container(
      key: ValueKey('option-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? HighlightColors.background(dark, uncertain: uncertain)
            : null,
        border: Border.all(
            color: highlighted
                ? color
                : (dark ? const Color(0xFF3A4046) : const Color(0xFFD3D9D6)),
            width: highlighted ? 2 : 1),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: fontSize,
                  color: highlighted ? color : null,
                  fontWeight: highlighted ? FontWeight.bold : null)),
          if (highlighted) ...[
            const SizedBox(width: 6),
            Icon(Icons.check, size: 18, color: color, key: ValueKey('check-$label')),
          ],
        ],
      ),
    );
  }

  Widget _optionRow({
    required String key,
    required String label,
    required String text,
    required bool highlighted,
    required bool dark,
    required Color fg,
    bool uncertain = false,
  }) {
    final color = HighlightColors.text(dark, uncertain: uncertain);
    return Container(
      key: ValueKey(key),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: highlighted
          ? BoxDecoration(
              color: HighlightColors.background(dark, uncertain: uncertain),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border(left: BorderSide(color: color, width: 4)),
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border(
                  left: BorderSide(
                      color: dark
                          ? const Color(0xFF2E3439)
                          : const Color(0xFFE7EBE9),
                      width: 4)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: fontSize * 1.25,
            height: fontSize * 1.25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlighted
                  ? color.withValues(alpha: 0.16)
                  : (dark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              shape: BoxShape.circle,
            ),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: fontSize * 0.78,
                  fontWeight: FontWeight.bold,
                  color: highlighted ? color : fg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: MathText(
                text: text,
                style: TextStyle(
                    fontSize: fontSize,
                    height: 1.5,
                    color: highlighted ? color : fg),
              ),
            ),
          ),
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check,
                  size: fontSize, color: color, key: ValueKey('check-$label')),
            ),
        ],
      ),
    );
  }

  /// 解析区：加一层浅底容器，与题干形成层级。
  Widget _analysisBlock(bool dark, Color secondary, Color fg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF171A1D) : const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
            color: dark ? const Color(0xFF262B2F) : const Color(0xFFE9EDEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: secondary),
              const SizedBox(width: 5),
              Text('解析',
                  style: TextStyle(
                      fontSize: fontSize * 0.78,
                      fontWeight: FontWeight.w700,
                      color: secondary)),
            ],
          ),
          const SizedBox(height: 6),
          MathText(
            text: question.analysis,
            style: TextStyle(fontSize: fontSize * 0.92, height: 1.6, color: fg),
          ),
        ],
      ),
    );
  }

  List<Widget> _answerBlock(bool dark, bool uncertain) {
    final color = HighlightColors.text(dark, uncertain: uncertain);
    return [
      Row(
        children: [
          Text('答案',
              style: TextStyle(
                  fontSize: fontSize * 0.78,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.grey[400]! : Colors.grey[700]!)),
          // 用户需求 2：答案为 AI 推断时必须注明。
          if (question.answerGuessed) ...[
            const SizedBox(width: 6),
            Text('（AI 猜测）',
                style: TextStyle(
                    fontSize: fontSize * 0.78,
                    fontWeight: FontWeight.w700,
                    color: HighlightColors.incomplete(dark))),
          ],
        ],
      ),
      const SizedBox(height: 5),
      Container(
        key: const ValueKey('answer-block'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HighlightColors.background(dark, uncertain: uncertain),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _answerText(dark, color)),
            const SizedBox(width: 8),
            Icon(
                uncertain ? Icons.help_outline : Icons.check_circle,
                size: fontSize,
                color: color),
          ],
        ),
      ),
    ];
  }

  /// 答案正文（用户反馈 15）：主观/填空的结构化多行答案按行渲染，
  /// 每行独立成条（保留 AI 给的 ①②③ / 1. 这类序号），单行答案原样显示。
  Widget _answerText(bool dark, Color color) {
    final text = question.answerText ?? '';
    final style = TextStyle(
        fontSize: fontSize, color: color, height: 1.5, fontWeight: FontWeight.w600);
    if (!question.hasStructuredAnswer) {
      return MathText(text: text, style: style);
    }
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Column(
      key: const ValueKey('answer-structured'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_numbering.hasMatch(lines[i])) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(child: MathText(text: lines[i], style: style)),
              ],
            ),
          ),
      ],
    );
  }

  /// 行首已有的编号/项目符号（①②③ / 1. / (1) / 一、 / - / •）。
  static final _numbering = RegExp(
      r'^\s*([①-⑳]|[0-9]+\s*[.、)）]|[（(]\s*[0-9一二三四五六七八九十]+\s*[)）]|[一二三四五六七八九十]+\s*[、.]|[-*•·])');

  /// AI 给的告警（未识别到选项 / 答案与选项不匹配 / 答案为图中猜测…）。
  ///
  /// 用户反馈 9：原来是横向 `Wrap` 里的药丸，**药丸里的 Text 不换行**，
  /// 一句长提示（例如「答案为图中猜测答案，且材料……「）会直接顶出屏幕边界。
  /// 改成一行一块、正文 `Expanded` 自动换行。
  Widget _warnings(bool dark) {
    final color = HighlightColors.reviewBadge;
    final text = HighlightColors.warnText(dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in question.warnings)
          Container(
            key: ValueKey('warning-$w'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: HighlightColors.reviewBadgeBackground
                  .withValues(alpha: dark ? 0.16 : 0.55),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    w,
                    style: TextStyle(
                        fontSize: fontSize * 0.82, height: 1.5, color: text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _noAnswerHint(bool dark) {
    return Container(
      key: const ValueKey('no-answer-hint'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? Colors.orange[900]!.withValues(alpha: 0.22) : Colors.orange[50],
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
            color: (dark ? Colors.orange[200]! : Colors.orange[800]!)
                .withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.help_outline,
              size: 16, color: dark ? Colors.orange[200] : Colors.orange[800]),
          const SizedBox(width: 8),
          Text('未识别出答案',
              style: TextStyle(
                  fontSize: fontSize * 0.9,
                  color: dark ? Colors.orange[200] : Colors.orange[800])),
        ],
      ),
    );
  }
}

/// 阅读材料面板（用户反馈 15）：阅读类题目的文章原文，**默认折叠**，
/// 点标题条展开/收起——材料通常很长，展开会把它下面真正要看的题干与答案
/// 挤出屏幕。空材料不会渲染（调用方已判 `hasMaterial`）。
class _MaterialPanel extends StatefulWidget {
  final String material;
  final bool dark;
  final double fontSize;

  const _MaterialPanel({
    required this.material,
    required this.dark,
    required this.fontSize,
  });

  @override
  State<_MaterialPanel> createState() => _MaterialPanelState();
}

class _MaterialPanelState extends State<_MaterialPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final theme = Theme.of(context);
    final accent = HighlightColors.reviewBadge;
    final lineCount = widget.material
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;
    return Container(
      key: const ValueKey('question-material'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B1E21) : const Color(0xFFF5F7F9),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
            color: dark ? const Color(0xFF2A2F34) : const Color(0xFFE3E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('material-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 15, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _open
                          ? '阅读材料（点击收起）'
                          : '阅读材料（$lineCount 行，点击展开）',
                      style: TextStyle(
                          fontSize: widget.fontSize * 0.8,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MathText(
                key: const ValueKey('material-body'),
                text: widget.material,
                style: TextStyle(
                    fontSize: widget.fontSize * 0.92,
                    height: 1.65,
                    color: theme.colorScheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
