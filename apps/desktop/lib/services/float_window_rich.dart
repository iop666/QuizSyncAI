/// 悬浮窗内容区的**富文本渲染**（M40）。
///
/// 为什么要有它：M34 为了治卡顿把内容改成 `TextPainter` 直排，代价是**公式按 LaTeX
/// 源码显示**、化学式没有上下标、材料里的表格退化成纯文本 —— 用户连着两轮不接受。
/// 与其把 `MathText` 的分块解析/化学小标/表格再实现一遍，不如直接把**主界面同一套
/// `QuestionCard`** 离屏渲成位图：它与主界面天然一致，以后主界面改了悬浮窗也跟着改。
///
/// 和 M33 那版的关键区别：**按片渲染**（M39 的切片骨架）。一帧只出可见区覆盖的
/// 1–2 片（+1 片预取），所以「每帧跑一遍 widget 管线」那个卡顿源头不存在了 ——
/// 滚动/悬停帧仍然只做内存拷贝，widget 管线只在外观或内容变化时跑。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'float_window_content.dart' show questionsSignature;
import 'float_window_view.dart';

/// 一次富文本渲染的全部输入（任何一项变了都要重新量高度 / 重新出图）。
class FloatRichSpec {
  const FloatRichSpec({
    required this.questions,
    required this.width,
    required this.fontSize,
    required this.fontWeight,
    required this.minimal,
    required this.accent,
    required this.dark,
    required this.emptyText,
    required this.failed,
  });

  final List<Question> questions;

  /// 内容区宽度（逻辑像素）。
  final double width;
  final double fontSize;
  final int fontWeight;

  /// 极简模式（只看题目答案）。
  final bool minimal;

  /// 主色（配色表里的 seed，决定卡片配色）。
  final int accent;
  final bool dark;

  /// 没有内容时显示的话（[failed] 为真时表示排版失败）。
  final String emptyText;
  final bool failed;

  /// 指纹：变了才重新量高度 / 重新出图。
  ///
  /// ⚠️ **只允许放「会影响画面」的字段**（M40 实测教训）：指纹里一旦带上
  /// `updatedAt` / `lamport` 这类记账字段，前台「每秒一次」的轮询碰到它就会把
  /// 整篇内容重渲一遍 —— 用户看到的是「滑动还是更卡」（内容越长越明显：
  /// 20 题 ≈ 3 片 ≈ 1.2 s，相当于一直在渲染）。所以这里逐字看题目内容本身。
  int get key => Object.hash(
        accent,
        dark,
        (width * 10).round(),
        (fontSize * 10).round(),
        fontWeight,
        minimal,
        // 没有题目时才看占位文案（有题目时它根本不显示）。
        questions.isEmpty ? Object.hash(emptyText, failed ? 1 : 0) : 0,
        Object.hashAll(questions.map((q) => Object.hash(
              q.questionId,
              q.questionNo,
              q.stem,
              q.material,
              q.type,
              Object.hashAll(q.options.map((o) => '${o.label}|${o.text}')),
              Object.hashAll(q.choice),
              q.answerText,
              q.analysis,
              q.confidence,
              q.needReview,
              q.incomplete,
              q.answerGuessed,
              Object.hashAll(q.warnings),
            ))),
      );

  /// 纯文本指纹（拼进合成器的内容键，避免「高度一样但内容不同」撞车）。
  int get contentSignature => Object.hash(
        key,
        questionsSignature(questions),
        failed ? 1 : 0,
      );
}

/// 富文本内容的「片」高（逻辑像素）。
///
/// 与 [kFloatContentTileHeight]（图元直排用）分开：图元直排便宜、片小命中率高；
/// 富文本一次出图 300–500 ms，配合「内容一变就把所有片渲完」，片高只影响
/// 「一次渲多少张」与单片内存，不影响滚动手感。
const double kFloatRichChunkHeight = 2048;

/// 量内容高度（可注入：单测塞假实现以避开离屏管线）。
typedef FloatRichMeasurer = Future<double> Function(FloatRichSpec spec);

/// 栅格化一片内容（可注入：[tileTop] 是内容区内偏移，逻辑像素）。
typedef FloatRichTileRasterizer = Future<Uint8List> Function(
  FloatRichSpec spec, {
  required double tileTop,
  required double tileHeight,
  required double devicePixelRatio,

  /// 内容区底色（不透明）。分层窗口里**必须铺满**：透明像素会直接露出桌面。
  required int backgroundArgb,
  double opacity,
});

/// 量内容自然高度（逻辑像素；**不栅格化**，比出图便宜得多）。失败返回 0。
Future<double> measureRichContentHeight(FloatRichSpec spec) async {
  final laid = await _layout(spec, devicePixelRatio: 1);
  if (laid == null) return 0;
  final h = laid.height;
  laid.detach();
  return h;
}

/// 栅格化「内容坐标 `[tileTop, tileTop + tileHeight)`」这一段，返回**预乘 BGRA**。
Future<Uint8List> rasterRichTile(
  FloatRichSpec spec, {
  required double tileTop,
  required double tileHeight,
  required double devicePixelRatio,
  required int backgroundArgb,
  double opacity = 1,
}) async {
  final pw = (spec.width * devicePixelRatio).round().clamp(1, 8192);
  final ph = (tileHeight * devicePixelRatio).round().clamp(1, 8192);
  final laid = await _layout(spec,
      devicePixelRatio: devicePixelRatio,
      tileTop: tileTop,
      tileHeight: tileHeight,
      backgroundArgb: backgroundArgb);
  if (laid == null) return Uint8List(pw * ph * 4);
  final image = laid.image;
  laid.detach();
  if (image == null) return Uint8List(pw * ph * 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return Uint8List(pw * ph * 4);
  final src = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final out = premultipliedBgra(src, opacity);
  // 出图的像素数与预期不符时（尺寸被 clamp 过）按预期长度截/补，别让上层拿到短缓冲。
  if (out.length == pw * ph * 4) return out;
  final fixed = Uint8List(pw * ph * 4);
  fixed.setRange(0, out.length < fixed.length ? out.length : fixed.length, out);
  return fixed;
}

/// 离屏排版/出图的一次结果。
class _Laid {
  _Laid(this.height, this.image, this._owner, this._view);

  final double height;
  final ui.Image? image;
  final PipelineOwner _owner;
  final RenderView _view;

  /// 拆树：离屏管线每次用完就丢，不拆会一直挂着 RenderObject 与图层。
  void detach() {
    _view.child = null;
    _owner.rootNode = null;
  }
}

/// 真正的离屏管线：`PipelineOwner + RenderView + RenderRepaintBoundary`。
///
/// 要点（M33/M39 实测）：
/// - 把 `RenderRepaintBoundary` 放进 `RenderPositionedBox`（= `Align`）里，它拿到**松约束**
///   并按内容自然尺寸收拢 → `boundary.size.height` 就是「内容有多高」，不用两遍排版；
/// - [tileHeight] 为 null 时只量高度（不出图）；给定时把内容按 [tileTop] 上移、裁到该高度，
///   于是位图正好是那一片（按片出图见 M39）。
Future<_Laid?> _layout(
  FloatRichSpec spec, {
  required double devicePixelRatio,
  int backgroundArgb = 0,
  double? tileTop,
  double? tileHeight,
}) async {
  final view = ui.PlatformDispatcher.instance.implicitView;
  if (view == null) return null;
  const limit = 20000.0;
  final rootHeight = tileHeight ?? limit;
  final boundary = RenderRepaintBoundary();
  final owner = PipelineOwner();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(Size(spec.width, rootHeight)),
      physicalConstraints: BoxConstraints.tight(
          Size(spec.width * devicePixelRatio, rootHeight * devicePixelRatio)),
      devicePixelRatio: devicePixelRatio,
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
  );
  owner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final buildOwner = BuildOwner(focusManager: FocusManager());
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: _RichHost(
      theme: _themeFor(spec),
      spec: spec,
      tileTop: tileTop,
      tileHeight: tileHeight,
      backgroundArgb: backgroundArgb,
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner.buildScope(element);
  owner.flushLayout();
  // 只量高度时到此为止：`flushPaint` + `toImage` 才是贵的（探针实测量一次
  // 662 ms → 只排版后降到几十毫秒），出图才需要它们。
  if (tileHeight != null) {
    owner.flushCompositingBits();
    owner.flushPaint();
  }

  final height = boundary.size.height;
  ui.Image? image;
  if (tileHeight != null && height > 0) {
    image = await boundary.toImage(pixelRatio: devicePixelRatio);
  }
  buildOwner.finalizeTree();
  return _Laid(height, image, owner, renderView);
}

/// 离屏树的宿主环境：`MediaQuery + Directionality + Material + Theme` 一样不能少，
/// 否则 `QuestionCard` 里的 `Theme.of` / `DefaultTextStyle` 取不到。
class _RichHost extends StatelessWidget {
  const _RichHost({
    required this.theme,
    required this.spec,
    required this.tileTop,
    required this.tileHeight,
    required this.backgroundArgb,
  });

  final ThemeData theme;
  final FloatRichSpec spec;
  final double? tileTop;
  final double? tileHeight;
  final int backgroundArgb;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (spec.questions.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Text(
          spec.failed ? '内容渲染失败，可在主窗口里重新分析' : spec.emptyText,
          style: TextStyle(
              fontSize: spec.fontSize,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in spec.questions)
            QuestionCard(
              question: q,
              fontSize: spec.fontSize,
              fontWeight: spec.fontWeight,
              // 悬浮窗里没有别的把握率线索，所以总是显示。
              alwaysShowConfidence: true,
            ),
          const SizedBox(height: 10),
        ],
      );
    }

    var body = content;
    final tileH = tileHeight;
    if (tileH != null) {
      // 只画「内容坐标 [tileTop, tileTop+tileHeight)」这一片：外层给定高度并裁剪，
      // 内层按自然高度布局、再整体上移 tileTop。
      body = SizedBox(
        width: spec.width,
        height: tileH,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: spec.width,
            maxWidth: spec.width,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(0, -(tileTop ?? 0)),
              child: content,
            ),
          ),
        ),
      );
    }

    return MediaQuery(
      data: MediaQueryData(devicePixelRatio: 1, size: Size(spec.width, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          // 内容区底色必须铺满：分层窗口里透明像素会露出桌面（M40 探针实测）。
          color: backgroundArgb == 0
              ? const Color(0xFFFFFFFF)
              : Color(backgroundArgb),
          child: Theme(
            data: theme,
            child: DefaultTextStyle(
              style: TextStyle(
                  fontSize: spec.fontSize,
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'MiSans'),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮窗配色 → `ThemeData`（按「明暗 + 主色」缓存：每帧造主题是 M34 踩过的坑）。
ThemeData _themeFor(FloatRichSpec spec) {
  final k = '${spec.dark ? 'd' : 'l'}|${spec.accent}';
  final hit = _themes[k];
  if (hit != null) return hit;
  final built = QuizSyncTheme.build(
    brightness: spec.dark ? Brightness.dark : Brightness.light,
    accent: spec.accent,
    fontFamily: 'MiSans',
    fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
  );
  _themes[k] = built;
  return built;
}

final Map<String, ThemeData> _themes = {};
