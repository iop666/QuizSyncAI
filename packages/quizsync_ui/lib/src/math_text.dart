import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 题目内容渲染（双端共用）。
///
/// 历史：M6 只做「`$...$` 行内公式」，M20 补上 LaTeX 原生的 `\(...\)` / `\[...\]`。
/// M21 用户反馈「展开材料时，题目/解析/答案的公式（包括化学成分的小标等）、表格
/// 显示不清晰」，于是这一版把**正文**也当结构化内容来渲染：
///
/// 1. **化学式**：`ZnCO3`、`Fe2+`、`H2O2` 这类裸写法（AI 在题干/材料/解析里几乎
///    不写 LaTeX）按元素符号切分，数字下沉成下标、电荷上浮成上标；
/// 2. **表格**：材料里的「空格对齐表」与 Markdown 竖线表都渲染成真表格
///    （空格对齐的列在比例字体下会挤成一团）；
/// 3. **公式分块**：`$$…$$` / `\[…\]` 一律独占一行；**过长的行内公式**
///    （超过当前宽度大致能容纳的字符数）也搬到独立一行，避免它作为一个
///    不可断行的整体把整段挤出屏幕；
/// 4. **行内公式改回 `MathStyle.text`**：原来一律用 display 风格，短公式
///    （`$L=0.50\ \mathrm{m}$`）会把行高撑得忽高忽低。
///
/// 解析失败仍然回退为等宽源码（不白屏）；无公式无表格无化学式的纯文本走
/// `Text` 快路径，行为与以前完全一致（`find.text` 仍能命中）。
class MathText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const MathText({super.key, required this.text, required this.style});

  /// 公式定界符（M20）：四种写法都认。
  ///
  /// 顺序有意义：`$$...$$` 必须排在 `$...$` 前面，否则 `$$x$$` 会被拆成两段
  /// 空公式；`\[...\]` / `\(...\)` 同理要先于任何单字符形式尝试。
  static final _mathRe = RegExp(
    r'\$\$[\s\S]+?\$\$' // $$...$$ 独立公式
    r'|\\\[[\s\S]+?\\\]' // \[...\] 独立公式
    r'|\$[^$\n]+?\$' // $...$ 行内公式
    r'|\\\([\s\S]+?\\\)', // \(...\) 行内公式
  );

  static bool _isDisplayDelimiter(String raw) =>
      raw.startsWith(r'$$') || raw.startsWith(r'\[');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 行内公式能容纳的字符数：按「一个字符 ≈ 11 逻辑像素」粗估，窄屏（手机）
      // 会自动把更多长公式搬成块级；上下限防止极端窗口把阈值拉飞。
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
      final maxInline = (width / 11).clamp(24.0, 96.0).toInt();
      final blocks = parseContentBlocks(text, maxInlineChars: maxInline);

      // 快路径：纯文本（无公式/表格/化学式）保持老的 `Text`，选择与查找行为不变。
      // 注意必须连**化学式**一起判 —— 只判「只有一个 TextRun」会让
      // 「ZnCO3 与 Fe2+ 反应」这种正文直接绕过小标渲染（M21 实测踩到）。
      if (blocks.length == 1 && blocks.first is ParagraphBlock) {
        final runs = (blocks.first as ParagraphBlock).runs;
        if (runs.length == 1 &&
            runs.first is TextRun &&
            !hasInlineFormatting((runs.first as TextRun).text)) {
          return Text(text, style: style);
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in blocks) _renderBlock(context, b),
        ],
      );
    });
  }

  Widget _renderBlock(BuildContext context, ContentBlock block) {
    switch (block) {
      case ParagraphBlock(:final runs):
        return Text.rich(
          TextSpan(children: [
            for (final run in runs)
              if (run is TextRun)
                ...plainSpans(run.text, style)
              else
                _MathSpan(latex: (run as MathRun).latex, style: style),
          ]),
          style: style,
        );
      case FormulaBlock(:final latex):
        return _blockFormula(latex);
      case TableBlock(:final rows, :final header):
        return _table(context, rows, header: header);
    }
  }

  /// 块级公式：独占一行、可横向滚动（再长也不会被裁掉）。
  Widget _blockFormula(String latex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          latex,
          textStyle: style,
          mathStyle: MathStyle.display,
          onErrorFallback: (e) => _fallback(latex),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<List<String>> rows,
      {required bool header}) {
    final scheme = Theme.of(context).colorScheme;
    final divider = scheme.outlineVariant.withValues(alpha: 0.7);
    final cellStyle = style.copyWith(fontSize: (style.fontSize ?? 14) * 0.95);
    final headerStyle = cellStyle.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: divider, width: 0.6),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: header && r == 0
                    ? BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6))
                    : null,
                children: [
                  for (final cell in rows[r])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Text.rich(TextSpan(
                        children: plainSpans(
                            cell, header && r == 0 ? headerStyle : cellStyle),
                      )),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(String latex) => Text(
        latex,
        key: const ValueKey('math-fallback'),
        style: style.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Consolas', 'Courier New'],
        ),
      );
}

// ============================================================
// 内容块模型（纯数据，单测直接断言解析结果）
// ============================================================

sealed class InlineRun {
  const InlineRun();
}

/// 普通文字（内部还会做化学式处理）。
class TextRun extends InlineRun {
  final String text;
  const TextRun(this.text);
}

/// 行内公式。
class MathRun extends InlineRun {
  final String latex;
  const MathRun(this.latex);
}

sealed class ContentBlock {
  const ContentBlock();
}

class ParagraphBlock extends ContentBlock {
  final List<InlineRun> runs;
  const ParagraphBlock(this.runs);
}

/// 独立成行的公式。
class FormulaBlock extends ContentBlock {
  final String latex;
  const FormulaBlock(this.latex);
}

/// 表格（空格对齐表或 Markdown 竖线表）。
class TableBlock extends ContentBlock {
  final List<List<String>> rows;

  /// Markdown 表能明确声明表头；空格对齐表按**数据**处理（第一行往往就是
  /// 一组数值，加粗反而错）。
  final bool header;

  const TableBlock(this.rows, {this.header = false});
}

// ============================================================
// 解析
// ============================================================

/// 把一段文本切成「段落 / 公式块 / 表格块」。
///
/// [maxInlineChars] 是行内公式的长度上限（由调用方按可用宽度算），超过就搬成
/// 块级公式 —— 行内公式是一个**不可断行**的整体，太长会把整段挤出屏幕。
List<ContentBlock> parseContentBlocks(String text, {int maxInlineChars = 40}) {
  final blocks = <ContentBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final chunk = paragraph.join('\n');
    paragraph.clear();
    blocks.addAll(_paragraphBlocks(chunk, maxInlineChars));
  }

  final lines = text.split('\n');
  var i = 0;
  while (i < lines.length) {
    final md = _markdownTableAt(lines, i);
    if (md != null) {
      flushParagraph();
      blocks.add(md.$1);
      i = md.$2;
      continue;
    }
    final space = _spaceTableAt(lines, i);
    if (space != null) {
      flushParagraph();
      blocks.add(space.$1);
      i = space.$2;
      continue;
    }
    paragraph.add(lines[i]);
    i++;
  }
  flushParagraph();

  // 全空文本也要给出一块，避免返回空列表让调用方拿到空布局。
  if (blocks.isEmpty) blocks.add(const ParagraphBlock([TextRun('')]));
  return blocks;
}

/// 段落 → 「段落块 + 块级公式块」交替序列。
List<ContentBlock> _paragraphBlocks(String text, int maxInlineChars) {
  final out = <ContentBlock>[];
  final runs = <InlineRun>[];
  var pos = 0;

  void flushRuns() {
    if (runs.isEmpty) return;
    out.add(ParagraphBlock(List<InlineRun>.from(runs)));
    runs.clear();
  }

  for (final m in MathText._mathRe.allMatches(text)) {
    final raw = m.group(0)!;
    final latex = _latexOf(raw);
    if (m.start > pos) runs.add(TextRun(text.substring(pos, m.start)));
    if (MathText._isDisplayDelimiter(raw) || latex.length > maxInlineChars) {
      flushRuns();
      out.add(FormulaBlock(latex));
    } else {
      runs.add(MathRun(latex));
    }
    pos = m.end;
  }
  if (pos < text.length) runs.add(TextRun(text.substring(pos)));
  flushRuns();
  if (out.isEmpty) out.add(ParagraphBlock([TextRun(text)]));
  return out;
}

/// 去掉定界符：两字符的（`$$`、`\[`、`\(`）去 2，单字符的（`$`）去 1。
String _latexOf(String raw) {
  final two =
      raw.startsWith(r'$$') || raw.startsWith(r'\[') || raw.startsWith(r'\(');
  return two ? raw.substring(2, raw.length - 2) : raw.substring(1, raw.length - 1);
}

final _pipeRow = RegExp(r'^\s*\|.*\|\s*$');
final _pipeSep = RegExp(r'^\s*\|[\s:|-]+\|\s*$');

/// Markdown 竖线表（`| a | b |` + `|---|---|`）。返回 (块, 下一行下标)。
(TableBlock, int)? _markdownTableAt(List<String> lines, int start) {
  if (start + 1 >= lines.length) return null;
  if (!_pipeRow.hasMatch(lines[start])) return null;
  if (!_pipeSep.hasMatch(lines[start + 1])) return null;
  final rows = <List<String>>[_splitPipe(lines[start])];
  var i = start + 2;
  while (i < lines.length && _pipeRow.hasMatch(lines[i])) {
    rows.add(_splitPipe(lines[i]));
    i++;
  }
  if (rows.first.length < 2) return null;
  return (TableBlock(rows, header: true), i);
}

List<String> _splitPipe(String line) {
  final t = line.trim();
  final body = t.startsWith('|') ? t.substring(1) : t;
  final inner = body.endsWith('|') ? body.substring(0, body.length - 1) : body;
  return inner.split('|').map((c) => c.trim()).toList();
}

final _multiSpace = RegExp(r'\s{2,}');

/// 空格对齐表：连续 >=2 行，每行被 2+ 空格切成 >=3 段且段数相同。
///
/// 用户真实数据里的样子（生物题材料）：
/// ```
/// 光照强度/klx    0    2    4    6    8
/// CO₂变化量/mg    +44    +8    -22    -44    -44
/// ```
/// 这种列在比例字体下会挤成一行，必须按表格画。
(TableBlock, int)? _spaceTableAt(List<String> lines, int start) {
  if (start >= lines.length) return null;
  final first = _spaceCells(lines[start]);
  if (first == null) return null;
  final rows = <List<String>>[first];
  var i = start + 1;
  while (i < lines.length) {
    final cells = _spaceCells(lines[i]);
    if (cells == null || cells.length != first.length) break;
    rows.add(cells);
    i++;
  }
  if (rows.length < 2) return null;
  return (TableBlock(rows), i);
}

List<String>? _spaceCells(String line) {
  final t = line.trim();
  if (t.length > 160) return null;
  final cells = t.split(_multiSpace);
  if (cells.length < 3) return null;
  if (cells.any((c) => c.trim().isEmpty)) return null;
  return cells;
}

// ============================================================
// 化学式 / 缺字符号
// ============================================================

/// 元素符号表（判化学式用）。宁可漏判也不要误判普通英文缩写。
const _elements = {
  'H', 'He', 'Li', 'Be', 'B', 'C', 'N', 'O', 'F', 'Ne', 'Na', 'Mg', 'Al',
  'Si', 'P', 'S', 'Cl', 'Ar', 'K', 'Ca', 'Sc', 'Ti', 'V', 'Cr', 'Mn', 'Fe',
  'Co', 'Ni', 'Cu', 'Zn', 'Ga', 'Ge', 'As', 'Se', 'Br', 'Kr', 'Rb', 'Sr',
  'Y', 'Zr', 'Nb', 'Mo', 'Tc', 'Ru', 'Rh', 'Pd', 'Ag', 'Cd', 'In', 'Sn',
  'Sb', 'Te', 'I', 'Xe', 'Cs', 'Ba', 'La', 'Ce', 'Pr', 'Nd', 'Pm', 'Sm',
  'Eu', 'Gd', 'Tb', 'Dy', 'Ho', 'Er', 'Tm', 'Yb', 'Lu', 'Hf', 'Ta', 'W',
  'Re', 'Os', 'Ir', 'Pt', 'Au', 'Hg', 'Tl', 'Pb', 'Bi', 'Po', 'At', 'Rn',
  'Fr', 'Ra', 'Ac', 'Th', 'Pa', 'U', 'Np', 'Pu', 'Am', 'Cm', 'Bk', 'Cf',
  'Es', 'Fm', 'Md', 'No', 'Lr', 'Rf', 'Db', 'Sg', 'Bh', 'Hs', 'Mt', 'Ds',
  'Rg', 'Cn', 'Nh', 'Fl', 'Mc', 'Lv', 'Ts', 'Og',
};

/// 化学式候选：元素符号 + 数字（可带结尾电荷），且不紧贴英文字母。
final _chemRe = RegExp(
    r'(?<![A-Za-z])'
    r'(?:[A-Z][a-z]?(?:[A-Z][a-z]?|\d+)*(?:[+\u2212-])?'
    // 单独的电子写法 `e-` / `e+`（小写 e，AI 在离子方程式里就是这么写的）
    r'|e[+\u2212-])'
    // 电荷后面不会紧跟数字或字母：
    //   `2H2O-4e-` 里 `H2O` 后面那个 `-` 是**减号**（紧跟 4），不能当电荷；
    //   `Fe-Cu`（紧跟 C）、`e-mail`（紧跟 m）、`1e-5`（紧跟 5）同理。
    r'(?![\dA-Za-z])');
final _chemPart = RegExp(r'[A-Za-z][a-z]?|\d+|[+\u2212-]');

/// MiSans 里**没有** `⇌`（U+21CC，化学平衡箭头，用户数据里出现 10 次），
/// 走系统字体回退不保险；KaTeX 自带这个字形，直接当行内公式画。
const _kEquilibrium = '⇌';

/// 这段文字里有没有需要特殊渲染的东西（化学式小标或化学平衡箭头）。
///
/// 供 `MathText` 判定能不能走纯 `Text` 快路径 —— 漏判就会让化学式整段变成
/// 普通文字（用户报的「小标没显示」）。
bool hasInlineFormatting(String text) {
  if (text.contains(_kEquilibrium)) return true;
  for (final m in _chemRe.allMatches(text)) {
    if (isChemicalFormula(m.group(0)!)) return true;
  }
  return false;
}

/// 普通文字 → 富文本片段（化学式小标 + 平衡箭头）。
List<InlineSpan> plainSpans(String text, TextStyle style) {
  final out = <InlineSpan>[];
  var pos = 0;
  for (final m in _chemRe.allMatches(text)) {
    final raw = m.group(0)!;
    if (!isChemicalFormula(raw)) continue;
    if (m.start > pos) {
      _appendWithArrow(out, text.substring(pos, m.start));
    }
    out.add(WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _chemWidget(raw, style),
    ));
    pos = m.end;
  }
  if (pos < text.length) _appendWithArrow(out, text.substring(pos));
  if (out.isEmpty) out.add(TextSpan(text: text));
  return out;
}

/// 平衡箭头单独切出来（它要换成 KaTeX 字形）。
void _appendWithArrow(List<InlineSpan> out, String text) {
  var pos = 0;
  while (true) {
    final i = text.indexOf(_kEquilibrium, pos);
    if (i < 0) break;
    if (i > pos) out.add(TextSpan(text: text.substring(pos, i)));
    out.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Math.tex(r'\rightleftharpoons',
          onErrorFallback: (_) => const Text(_kEquilibrium)),
    ));
    pos = i + _kEquilibrium.length;
  }
  if (pos < text.length) out.add(TextSpan(text: text.substring(pos)));
}

/// 是不是一个化学式：整串能拆成「元素符号 + 数字 + 电荷」，且至少有一个数字
/// 或一个电荷（否则 `pH`、`MPa`、`Kp` 这类普通缩写会被当成化学式）。
///
/// 小写 `e` 单独放行：离子方程式里的电子 `2e-` 就是这么写的（用户反馈
/// 「Cu²⁺ + 2e⁻ 的 ⁻ 显示为 -」）。
bool isChemicalFormula(String token) {
  if (token.length > 16) return false;
  final parts = _chemPart.allMatches(token).map((m) => m.group(0)!).toList();
  if (parts.join() != token) return false;
  var elements = 0;
  var digits = 0;
  var charge = 0;
  for (final p in parts) {
    if (RegExp(r'^\d+$').hasMatch(p)) {
      digits++;
    } else if (p == '+' || p == '-' || p == '\u2212') {
      charge++;
    } else if (p == 'e') {
      // 电子：不是元素符号，但和元素一样是「一个正体字符」。
      elements++;
    } else if (RegExp(r'^[A-Z]').hasMatch(p)) {
      if (!_elements.contains(p)) return false;
      elements++;
    } else {
      return false;
    }
  }
  // 至少一个元素符号/电子（挡住 `2026`、`x2` 这种纯数字），且至少一个数字或
  // 电荷（挡住 `pH`、`MPa`、`USB` 这种普通缩写）。
  return elements > 0 && (digits > 0 || charge > 0);
}

/// 把化学式画成「基线对齐的小部件」：数字下沉成下标、电荷上浮成上标。
///
/// 用部件而不是 `FontFeature.subscripts()`：那个 OpenType 特征只管用得上它的
/// 字体 —— 桌面端随包的 MiSans 有 `subs`/`sups`，但安卓端用的是系统字体
/// （非小米机型就是 Roboto/Noto），能不能下沉完全看运气。自己算偏移两端一致。
Widget _chemWidget(String token, TextStyle style) {
  final base = style.fontSize ?? 14;
  final children = <Widget>[];
  final parts = _chemPart.allMatches(token).map((m) => m.group(0)!).toList();
  // 连续的字母段合并成一个 Text（`ZnCO`+下标`3`，而不是 Zn/C/O/3 四个部件）：
  // 部件越少，行内排版与「这段文字还在不在」的观感越接近原文。
  final letters = StringBuffer();

  void flushLetters() {
    if (letters.isEmpty) return;
    children.add(Text(letters.toString(), style: style));
    letters.clear();
  }

  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (p == '+' || p == '-' || p == '\u2212') {
      flushLetters();
      children.add(_shifted(p, style, base, up: true));
      continue;
    }
    if (!RegExp(r'^\d+$').hasMatch(p)) {
      letters.write(p);
      continue;
    }
    flushLetters();
    // 数字后面紧跟正负号 = 电荷（上标），否则是原子个数（下标）。
    final next = i + 1 < parts.length ? parts[i + 1] : '';
    final isCharge = next == '+' || next == '-' || next == '\u2212';
    children.add(_shifted(p, style, base, up: isCharge));
  }
  flushLetters();
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: children,
  );
}

Widget _shifted(String s, TextStyle style, double base, {required bool up}) {
  return Transform.translate(
    offset: Offset(0, up ? -base * 0.30 : base * 0.14),
    child: Text(
      s,
      style: style.copyWith(fontSize: base * 0.68, height: 1.0),
    ),
  );
}

// ============================================================
// 行内公式
// ============================================================

class _MathSpan extends WidgetSpan {
  _MathSpan({required String latex, required TextStyle style})
      : super(
          alignment: PlaceholderAlignment.middle,
          child: _mathWidget(latex, style),
        );
}

Widget _mathWidget(String latex, TextStyle style) {
  // 渲染失败（解析错误）→ onErrorFallback：
  // 回退为等宽字体原样显示源码（必须保留回退，不能白屏）。
  Widget fallback(Object error) => Text(
        latex,
        key: const ValueKey('math-fallback'),
        style: style.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Consolas', 'Courier New'],
        ),
      );
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Math.tex(
      latex,
      textStyle: style,
      // 行内用 text 风格：display 风格会把行高撑得忽高忽低（M21）。
      mathStyle: MathStyle.text,
      onErrorFallback: fallback,
    ),
  );
}
