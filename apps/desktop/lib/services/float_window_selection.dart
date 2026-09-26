/// 悬浮窗「极简模式」的**文本选区**（M42）：纯函数，可单测。
///
/// 为什么要自己算：悬浮窗是原生分层窗口 + 离屏渲染（见 `float_window_view.dart`
/// 顶部的取舍说明），**没有 widget 树**，所以没有 `SelectableText` 可用；
/// 坐标换算、命中判定、选区高亮矩形都得自己来。
///
/// 分工：
/// - 选区两个点存在**内容坐标系**（y 从 0 开始、不随滚动变）里 —— 滚动时选区
///   跟着内容一起走，不会「滚一下就选到别的字」；
/// - 这一层只算「哪些字被选中 + 高亮矩形 + 复制文本」，把矩形加进合成像素
///   （`FloatFrameComposer.selectionRects`）与写剪贴板分别由调用方做。
library;

import 'package:flutter/painting.dart';

import 'float_window_view.dart';

/// 一次拖选：锚点（按下处）与焦点（当前处），都是**内容坐标**。
class FloatTextSelection {
  const FloatTextSelection(this.anchor, this.focus);

  final Offset anchor;
  final Offset focus;

  bool get isEmpty => anchor == focus;

  FloatTextSelection to(Offset focus) => FloatTextSelection(anchor, focus);

  @override
  bool operator ==(Object other) =>
      other is FloatTextSelection && other.anchor == anchor && other.focus == focus;

  @override
  int get hashCode => Object.hash(anchor, focus);
}

/// 选区算出来的东西。
class FloatSelectionResult {
  const FloatSelectionResult({
    required this.rects,
    required this.text,
    required this.questionIds,
  });

  /// 高亮矩形（**内容坐标**）：调用方加上 `bodyRect.topLeft - (0, scroll)` 就是窗口坐标。
  final List<Rect> rects;

  /// 选中的纯文本（跨题目时用换行连接）。
  final String text;

  /// 选区覆盖到的题目 id（「复制本题答案」按滚动位置找题时也用得上）。
  final Set<String> questionIds;

  bool get isEmpty => text.isEmpty;

  static const FloatSelectionResult none =
      FloatSelectionResult(rects: [], text: '', questionIds: {});
}

/// 一个「读序位置」：第几个图元 + 图元内的字符下标。
class _Pos implements Comparable<_Pos> {
  const _Pos(this.node, this.offset);

  final int node;
  final int offset;

  @override
  int compareTo(_Pos other) =>
      node != other.node ? node.compareTo(other.node) : offset.compareTo(other.offset);

  bool operator >(_Pos other) => compareTo(other) > 0;
}

/// 参与选区的文本图元（按读序：先上后下、同一行先左后右）。
List<FloatNode> selectableNodes(List<FloatNode> nodes) {
  final list = nodes
      .where((n) =>
          n.kind == FloatNodeKind.text &&
          n.painter != null &&
          (n.painter!.text?.toPlainText().isNotEmpty ?? false))
      .toList();
  list.sort((a, b) {
    final byTop = a.rect.top.compareTo(b.rect.top);
    return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
  });
  return list;
}

String _plain(TextPainter tp) => tp.text?.toPlainText() ?? '';

/// 点落在哪个图元的哪个字符上。
///
/// 点落在图元之间的空隙里（题与题之间的留白）时按**离哪边近**归到上/下一题，
/// 这样从一题的末尾往下拖能自然地连到下一题。
_Pos _hit(List<FloatNode> nodes, Offset p) {
  for (var i = 0; i < nodes.length; i++) {
    final r = nodes[i].rect;
    if (p.dy < r.top) {
      // 在第一个「还没到」的图元之上：算它的开头（同一行则按 x 精确定位）。
      if (p.dy >= r.top - 4 && p.dx <= r.right) {
        return _Pos(i, _offsetAt(nodes[i], p));
      }
      return _Pos(i, 0);
    }
    if (p.dy <= r.bottom) {
      return _Pos(i, _offsetAt(nodes[i], p));
    }
  }
  final last = nodes.length - 1;
  return _Pos(last, _plain(nodes[last].painter!).length);
}

int _offsetAt(FloatNode n, Offset p) {
  final tp = n.painter!;
  final local = Offset(
    (p.dx - n.rect.left).clamp(0.0, n.rect.width),
    (p.dy - n.rect.top).clamp(0.0, n.rect.height),
  );
  return tp.getPositionForOffset(local).offset.clamp(0, _plain(tp).length);
}

/// 算选区：返回高亮矩形（内容坐标）与可复制文本。
///
/// [nodes] 是**内容坐标系**里的内容图元（`FloatContent.nodes`）。
FloatSelectionResult resolveSelection(
  List<FloatNode> nodes,
  FloatTextSelection? selection,
) {
  if (selection == null || selection.isEmpty) return FloatSelectionResult.none;
  final list = selectableNodes(nodes);
  if (list.isEmpty) return FloatSelectionResult.none;

  var a = _hit(list, selection.anchor);
  var b = _hit(list, selection.focus);
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }

  final rects = <Rect>[];
  final parts = <String>[];
  final ids = <String>{};
  for (var i = a.node; i <= b.node; i++) {
    final n = list[i];
    final tp = n.painter!;
    final full = _plain(tp);
    final start = (i == a.node ? a.offset : 0).clamp(0, full.length);
    final end = (i == b.node ? b.offset : full.length).clamp(0, full.length);
    if (end <= start) continue;
    if (n.questionId != null) ids.add(n.questionId!);
    // 选区高亮：用排版好的 `TextPainter` 自己算每一行的矩形（和真实字形一致）。
    for (final box in tp.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end))) {
      rects.add(box.toRect().shift(n.rect.topLeft).intersect(n.rect));
    }
    parts.add(full.substring(start, end));
  }
  if (parts.isEmpty) return FloatSelectionResult.none;
  return FloatSelectionResult(
      rects: rects, text: parts.join('\n'), questionIds: ids);
}
