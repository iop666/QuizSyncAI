import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/services/float_window_selection.dart';
import 'package:quizsync_desktop/services/float_window_view.dart';

/// M42：极简模式「可选中字符」的选区算法（**纯函数**）。
///
/// 悬浮窗没有 widget 树（原生分层窗口 + 离屏渲染），所以 `SelectableText` 用不了：
/// 「点在哪两个字之间」「高亮哪几行」「复制出来是哪一段」都得自己算。这一组用例
/// 把这些算术钉住 —— 它们错了，用户就会「选中的字和拖的位置对不上」。
///
/// 用例**不假设字体度量**：需要「第 i 个字的位置」时用 `TextPainter.getOffsetForCaret`
/// 现算（换字体/换字号都不会让用例变脆）。
FloatNode _text(String s, Rect r, {String? qid}) => FloatNode(
      kind: FloatNodeKind.text,
      rect: r,
      text: s,
      questionId: qid,
      painter: floatParagraph(
        s,
        const TextStyle(fontSize: 20, height: 1.0, color: Color(0xFF000000)),
        maxWidth: r.width,
        // ⚠ `floatParagraph` 的 `maxLines` 默认是 **1**（按钮标签那些只要一行）：
        // 这里必须显式给 0（不限行），否则换行会被丢掉、整个用例都测不到多行。
        maxLines: 0,
      ),
    );

/// 第 [index] 个字在**内容坐标**里的位置（加一点 x 偏移，落在字形里）。
///
/// `affinity: downstream` 是必须的：换行处那个下标（一行的头一个字）在默认的
/// 上游亲和性下会被报成**上一行的行尾**（`getOffsetForCaret` 的既有语义），
/// 那样算出来的点会落在上一行，测出来的选区起点就错了一个换行。
Offset _at(FloatNode n, int index) {
  final tp = n.painter!;
  final caret = tp.getOffsetForCaret(
      TextPosition(offset: index, affinity: TextAffinity.downstream),
      Rect.zero);
  return Offset(n.rect.left + caret.dx + 2, n.rect.top + caret.dy + 2);
}

int _len(FloatNode n) => n.painter!.text!.toPlainText().length;

void main() {
  // 两个文本图元：第一题两行、第二题两行，中间留 20 像素空隙。
  final body = <FloatNode>[
    _text('ABCDEFGH\nIJKLMNOP', const Rect.fromLTWH(10, 0, 200, 40), qid: 'q1'),
    _text('QRSTUVWX\nYZ012345', const Rect.fromLTWH(10, 60, 200, 40), qid: 'q2'),
  ];
  final t1 = body[0].painter!.text!.toPlainText();
  final t2 = body[1].painter!.text!.toPlainText();

  test('① 点一下（没有拖动）不算选区：没有高亮、也不复制东西', () {
    final p = _at(body[0], 3);
    final r = resolveSelection(body, FloatTextSelection(p, p));
    expect(r.isEmpty, isTrue);
    expect(r.rects, isEmpty);
    expect(resolveSelection(body, null).isEmpty, isTrue);
  });

  test('② 同一题里从第 i 个字拖到第 j 个字：选中的就是这一段', () {
    final r = resolveSelection(
        body, FloatTextSelection(_at(body[0], 1), _at(body[0], 5)));
    expect(r.text, t1.substring(1, 5));
    expect(r.questionIds, {'q1'});
    expect(r.rects, isNotEmpty);
    // 高亮矩形必须落在该图元内（否则会把高亮画到别的题上）。
    for (final rect in r.rects) {
      expect(body.first.rect.inflate(0.01).contains(rect.topLeft), isTrue);
      expect(rect.bottom <= body.first.rect.bottom + 0.01, isTrue);
    }
  });

  test('③ 跨题拖选：两题的文字用换行连起来，两个题目 id 都在', () {
    // 从第一题第二行中间拖到第二题第一行中间。
    final r = resolveSelection(
        body, FloatTextSelection(_at(body[0], 10), _at(body[1], 4)));
    expect(r.text, '${t1.substring(10)}\n${t2.substring(0, 4)}');
    expect(r.questionIds, {'q1', 'q2'});
    expect(r.rects.length, greaterThanOrEqualTo(2));
  });

  test('④ 从后往前拖（右下 → 左上）得到同一段文字', () {
    final forward = resolveSelection(
        body, FloatTextSelection(_at(body[0], 10), _at(body[1], 4)));
    final backward = resolveSelection(
        body, FloatTextSelection(_at(body[1], 4), _at(body[0], 10)));
    expect(backward.text, forward.text);
    expect(backward.rects.length, forward.rects.length);
  });

  test('⑤ 题与题之间的空隙归「下一题的开头」：从空隙往下拖就是下一题', () {
    // 空隙在 y 40..60：从空隙（y=50）拖到第二题里 → 第二题从头选起。
    final r = resolveSelection(
        body, FloatTextSelection(const Offset(20, 50), _at(body[1], 6)));
    expect(r.text, t2.substring(0, 6));
    expect(r.questionIds, {'q2'});
  });

  test('⑥ 从题内拖进空隙：整道题都被选中（不会连到下一题）', () {
    final r = resolveSelection(
        body, FloatTextSelection(_at(body[0], 4), const Offset(20, 50)));
    expect(r.text, t1.substring(4));
    expect(r.questionIds, {'q1'});
  });

  test('⑦ 拖到内容下方（超出最后一个图元）：选到最后一题末尾', () {
    final r = resolveSelection(
        body, FloatTextSelection(_at(body[0], 0), const Offset(0, 400)));
    expect(r.text, '$t1\n$t2');
    expect(_len(body[0]) + _len(body[1]), t1.length + t2.length);
  });

  test('⑧ 只认有排版结果的文本图元（按钮/色块不参与选字）', () {
    final nodes = <FloatNode>[
      _text('XYZ', const Rect.fromLTWH(0, 0, 100, 20), qid: 'q1'),
      const FloatNode(
          kind: FloatNodeKind.box, rect: Rect.fromLTWH(0, 20, 100, 20)),
      const FloatNode(
          kind: FloatNodeKind.text, rect: Rect.fromLTWH(0, 40, 100, 20)),
    ];
    expect(selectableNodes(nodes).length, 1);
    final r = resolveSelection(
        nodes, FloatTextSelection(_at(nodes[0], 0), const Offset(0, 100)));
    expect(r.text, 'XYZ');
    expect(r.rects.length, 1);
  });

  test('⑨ 读序 = 先上后下、同一行先左后右（和眼睛看到的一致）', () {
    final nodes = <FloatNode>[
      _text('right', const Rect.fromLTWH(120, 0, 80, 20), qid: 'r'),
      _text('left', const Rect.fromLTWH(0, 0, 80, 20), qid: 'l'),
      _text('below', const Rect.fromLTWH(0, 40, 80, 20), qid: 'b'),
    ];
    expect(selectableNodes(nodes).map((n) => n.questionId).toList(),
        ['l', 'r', 'b']);
  });
}
