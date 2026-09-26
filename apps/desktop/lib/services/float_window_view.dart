/// Windows 悬浮窗的**窗口外观层**（M33 重写 / M34 修订）：纯 Dart 的布局 + 离屏渲染。
///
/// 分工：题目内容由 `float_window_content.dart` **用 TextPainter 直接排版**
/// （M34 第 8 条：离屏渲染整张 `QuestionCard` 虽然格式最全，但每帧都要走一遍
/// widget → 位图管线，实测悬浮窗明显卡顿，改回文本为主 + 明显的题目轮廓），
/// 这一层负责 ① 顶部第一栏（图标按钮 + 识别状态）、② 底部 **Dock 栏**
/// （M34 第 4 条：悬停放大的两个识别按钮）、③ 识别中提示、
/// ④ 把内容图元按滚动位置裁进内容区。
///
/// 布局与命中判定**共用同一份图元列表**（带 id 的图元就是按钮），并把
/// **顶部第一栏的矩形**单独交给原生层当拖拽区（只有第一栏能拖窗口）。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart'
    show AppRadius, HighlightColors, QuizSyncTheme;

/// 悬浮窗里的按钮 id（原生窗口把点击换算成这些 id，Dart 侧派发动作）。
abstract final class FloatAction {
  /// 顶部：下一条 / 上一条识别结果（M34 第 3 条：两者位置互换，
  /// 现在右边是「下一条」，读起来就是 ◀ ▶）。
  static const String next = 'next';
  static const String prev = 'prev';

  /// 顶部：重新识别当前这一次（重新调用 AI）。
  static const String regenerate = 'regenerate';

  /// 顶部：极简模式（只看题目答案）。
  static const String toggleMinimal = 'toggle-minimal';

  /// 顶部：锁定 / 解锁位置（最后一个）。
  static const String toggleLock = 'toggle-lock';

  /// 底部 Dock：默认识别（截一张图直接识别）。
  static const String capture = 'capture';

  /// 底部 Dock：进入多页识别（加第一张图）。
  static const String multiPage = 'multi-page';

  /// 底部 Dock（**只在默认模式出现**）：复制**这一次识别的全部内容**。
  ///
  /// 用户口径（M43 第 2 条）：「修改功能为复制识别内容，点击直接复制本次识别的内容」，
  /// 而且它排在三个按钮的**最后一个**。
  static const String copyContent = 'copy-content';

  /// 多页模式：继续添加页面。
  static const String addPage = 'add-page';

  /// 多页模式：结束并上传本次全部页面。
  static const String finishMulti = 'finish-multi';

  /// 多页模式：取消（丢弃暂存页、退出多页模式，不上传）。
  static const String cancelMulti = 'cancel-multi';
}

/// 图元种类。
enum FloatNodeKind { box, text }

/// 一帧里的一个图元。坐标都是**逻辑像素**，原点在窗口左上角。
class FloatNode {
  const FloatNode({
    required this.kind,
    required this.rect,
    this.id,
    this.text,
    this.fontSize = 12.5,
    this.argb = 0xFF000000,
    this.weight = 400,
    this.enabled = true,
    this.radius = 8,
    this.inBody = false,
    this.overlay = false,
    this.maxLines = 1,
    this.align = TextAlign.left,
    this.fontFamily,
    this.painter,
    this.borderArgb,
    this.borderWidth = 1,
    this.questionId,
  });

  final FloatNodeKind kind;
  final Rect rect;

  /// 可点击元素的 id（[FloatAction] 里的常量）；null = 不可点。
  final String? id;

  /// 这个文本图元属于哪道题（M42：极简模式的纯文本面板一题一个图元，
  /// 拖选与「复制本题答案」都靠它认题）。
  final String? questionId;
  final String? text;
  final double fontSize;
  final int argb;
  final int weight;

  /// 不可用时按钮仍画出来（置灰），但原生不会把它算进命中区。
  final bool enabled;
  final double radius;
  final bool inBody;

  /// true = 浮层（识别中提示 / 悬停提示）：画在内容之上，**单独出一张小图**，
  /// 这样悬停只重画这一小块（M36）。
  final bool overlay;
  final int maxLines;
  final TextAlign align;

  /// 图标字形用的字体家族（`Icons.xxx.fontFamily` = MaterialIcons）。
  final String? fontFamily;

  /// 已经排好版的文本（内容层缓存的 `TextPainter`）：有它就直接画，
  /// 不用每帧重新排版（M34 性能要点）。
  final TextPainter? painter;

  /// 描边色（题目轮廓）；null = 不描边。
  final int? borderArgb;
  final double borderWidth;

  bool get clickable => id != null && enabled;

  /// 平移进内容区（内容层的图元是「内容坐标系」，y 从 0 开始）。
  FloatNode intoBody(Offset delta) => FloatNode(
        kind: kind,
        rect: rect.shift(delta),
        id: id,
        text: text,
        fontSize: fontSize,
        argb: argb,
        weight: weight,
        enabled: enabled,
        radius: radius,
        inBody: true,
        overlay: overlay,
        maxLines: maxLines,
        align: align,
        fontFamily: fontFamily,
        painter: painter,
        borderArgb: borderArgb,
        borderWidth: borderWidth,
        questionId: questionId,
      );
}

/// 一帧：图元 + 几何（原生窗口只关心 id、rect、拖拽区）。
class FloatFrame {
  FloatFrame({
    required this.nodes,
    required this.bodyRect,
    required this.headerRect,
    required this.scrollMax,
    required this.width,
    required this.height,
    this.contentHeight = 0,
  });

  final List<FloatNode> nodes;
  final Rect bodyRect;

  /// 顶部第一栏：**只有这一条能拖动窗口**。
  final Rect headerRect;

  /// 内容可滚动的最大像素（0 = 不用滚）。
  final double scrollMax;
  final double width;
  final double height;

  /// 内容总高度（逻辑像素；0 = 无内容）。分块出图时内容图按它取高度。
  final double contentHeight;

  /// 可点击区域（逻辑像素）——原生侧乘 DPR 就是窗口内的物理矩形。
  Map<String, Rect> get hitRegions => {
        for (final n in nodes)
          if (n.clickable) n.id!: n.rect,
      };
}

/// 悬浮窗配色：6 套预设，**默认浅色系**，每套都从同一个种子色派生浅/深两种形态
/// —— 这样「配色」与「明暗模式」两个设置互不冲突。
class FloatWindowPalette {
  const FloatWindowPalette({
    required this.dark,
    required this.background,
    required this.header,
    required this.border,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.accentStrong,
    required this.answerStrong,
    required this.button,
    required this.buttonActive,
    required this.tooltip,
    required this.card,
    required this.analysisBg,
  });

  final bool dark;
  final int background;
  final int header;
  final int border;
  final int text;
  final int subtext;

  /// 主色（按钮底、徽标底、选区高亮用）。
  final int accent;

  /// **画在用窗口底色上的**主色（题号、强调文字）：保证与 [background] 的
  /// 对比度 ≥ 4.5:1（M43 第 3 条 —— 用户报「答案题号颜色和背景色高度接近」）。
  final int accentStrong;

  /// 答案文字的专用色（标绿/标黄那套），同样保证对比度 ≥ 4.5:1。
  final int answerStrong;

  final int button;
  final int buttonActive;
  final int tooltip;

  /// 题目卡片底（内容层画题目轮廓用）。
  final int card;

  /// 解析块底。
  final int analysisBg;

  /// 取配色（按「明暗 + 配色 id」缓存）。
  ///
  /// M34：这里原来每次都要 `QuizSyncTheme.build` 出一个 `ThemeData`，
  /// 而悬浮窗每推一帧就要取一次配色 —— 缓存掉，别再每帧造主题。
  factory FloatWindowPalette.of({
    required bool dark,
    required String paletteId,
  }) {
    final spec = floatWindowPaletteOf(paletteId);
    final key = '${dark ? 'd' : 'l'}|${spec.id}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final built = _build(dark: dark, seed: spec.seed);
    _cache[key] = built;
    return built;
  }

  static final Map<String, FloatWindowPalette> _cache = {};

  static FloatWindowPalette _build({required bool dark, required int seed}) {
    final seedColor = Color(seed);
    // 窗口底色 = 种子色按很低的比例叠在（浅色：白 / 深色：近黑）上。
    final base = dark ? const Color(0xFF12161A) : const Color(0xFFFFFFFF);
    final background = Color.alphaBlend(
        seedColor.withValues(alpha: dark ? 0.16 : 0.07), base);
    final header = Color.alphaBlend(
        seedColor.withValues(alpha: dark ? 0.26 : 0.13), base);
    final bg = background.toARGB32();
    return FloatWindowPalette(
      dark: dark,
      background: bg,
      header: header.toARGB32(),
      border: QuizSyncTheme.outline(
              dark ? Brightness.dark : Brightness.light)
          .toARGB32(),
      // 窗内的正文/次要文字用固定的两档（不再从 ThemeData 里取）。
      text: dark ? 0xFFE8ECEF : 0xFF1F2426,
      subtext: dark ? 0xFF9AA4AD : 0xFF5F6B76,
      accent: seed,
      // M43 第 3 条：**画在窗口底色上的**主色 / 答案色必须先满足对比度 ≥ 4.5:1
      // （用户报「极简模式的答案、题号颜色和背景色高度接近，不明显」）。
      accentStrong: ensureContrast(seed, bg),
      // 答案用**标绿**那套契约色（M44 第 4 条：用户要求「答案颜色改成绿色」）：
      // 门槛只给到 2.9:1（= 主界面在白卡片上的水平），所以浅色下就是 HighlightColors
      // 的原色 #16A34A —— 一眼能认出是绿色，不会被自动压暗成墨绿。
      answerStrong: ensureContrast(
          HighlightColors.text(dark).toARGB32(), bg,
          minRatio: 2.9),
      button: Color.alphaBlend(
              seedColor.withValues(alpha: dark ? 0.20 : 0.10), base)
          .toARGB32(),
      buttonActive: seedColor.withValues(alpha: 0.22).toARGB32(),
      tooltip: (dark ? const Color(0xFF2B3136) : const Color(0xFF30363B))
          .toARGB32(),
      // 卡片底比窗口底更白（浅色）／更亮一点（深色），才看得出题目轮廓。
      card: (dark ? const Color(0xFF1B2024) : const Color(0xFFFFFFFF))
          .toARGB32(),
      analysisBg: (dark ? const Color(0xFF171A1D) : const Color(0xFFF6F8F7))
          .toARGB32(),
    );
  }
}

/// 悬浮窗要显示的全部状态。
class FloatWindowModel {
  const FloatWindowModel({
    required this.palette,
    this.index = 0,
    this.total = 0,
    this.createdAt = 0,
    this.busy = false,
    this.busyText = '识别进行中…',
    this.minimal = false,
    this.locked = false,
    this.multiPage = false,
    this.stagedCount = 0,
    this.multiPageLimit = 6,
    this.fontScale = 1.0,
    this.scrollPx = 0,
    this.content = const [],
    this.contentHeight = 0,
    this.hoveredId,
    this.emptyText = '还没有识别记录，点下面的按钮开始识别',
    this.contentFailed = false,
    this.tipText,
  });

  final FloatWindowPalette palette;

  /// 当前看的是第几次识别（0 = 最新的一条）。
  final int index;
  final int total;
  final int createdAt;

  /// 正在识别（提示排在答案显示区的**下部**）。
  final bool busy;
  final String busyText;
  final bool minimal;
  final bool locked;
  final bool multiPage;
  final int stagedCount;
  final int multiPageLimit;
  final double fontScale;
  final double scrollPx;

  /// 内容图元（**内容坐标系**：y 从 0 开始，宽度 = 内容区宽度）。
  final List<FloatNode> content;

  /// 内容总高度（= 滚动量的基准）。
  final double contentHeight;

  /// 鼠标悬停的按钮 id（图标按钮的提示 / Dock 栏的放大）。
  final String? hoveredId;

  final String emptyText;

  /// 内容渲染失败（提示用户看主窗口）。
  final bool contentFailed;

  /// 一次性提示（M42：「已复制本题答案」/「已复制所选」），贴在内容区下方，
  /// 一两秒后由调用方清掉。
  final String? tipText;

  /// 「第 N/M 次识别」里的 N：最早的一次是第 1 次。
  int get humanIndex => total == 0 ? 0 : (total - index).clamp(1, total);
}

/// 顶部第一栏的按钮 id。
///
/// 只有它们**跟着鼠标悬停变样**（出提示气泡），所以也只有它们值得为一次
/// `WM_MOUSEMOVE` 重画一帧；底部两个识别按钮对悬停没有任何反应（用户看过
/// Dock 式放大之后明确否掉了），把它们的 hover 也当成「要重画」只会白卡一下。
const Set<String> kFloatHeaderActions = {
  FloatAction.next,
  FloatAction.prev,
  FloatAction.regenerate,
  FloatAction.toggleMinimal,
  FloatAction.toggleLock,
};

/// 窗口圆角半径（逻辑像素）：外观块按它裁剪、合成后再补一次角上的掩码。
const double kFloatWindowCornerRadius = 12;

/// WCAG 2.1 的**相对亮度**（0 = 黑，1 = 白）。
double relativeLuminance(int argb) {
  double channel(int v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

/// WCAG 对比度（1 = 完全相同，21 = 黑白）。
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 把 [argb] 朝「远离 [background]」的方向逐档调和，直到对比度 ≥ [minRatio]。
///
/// **为什么需要它**（M43 第 3 条）：悬浮窗的题号/答案用的都是配色的**种子色**，
/// 而窗口底色也是同一个种子色薄涂出来的 —— 深色下「紫罗兰」这类中明度种子与底色
/// 的对比度只有 2:1 上下，用户看到的就是「颜色和背景色高度接近，不明显」。
/// 这里只保证**够看清**，不改配色本身的色相（仍然是那套配色的颜色，只是更亮/更深）。
int ensureContrast(int argb, int background, {double minRatio = 4.5}) {
  if (contrastRatio(argb, background) >= minRatio) return argb;
  final towardWhite = relativeLuminance(background) < 0.5;
  var best = argb;
  for (var i = 1; i <= 40; i++) {
    final t = i / 40.0;
    final blended = Color.alphaBlend(
        (towardWhite ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
            .withValues(alpha: t),
        Color(argb));
    best = blended.toARGB32();
    if (contrastRatio(best, background) >= minRatio) return best;
  }
  return best;
}

/// 悬浮窗基准字体（12.5pt；竖屏窄窗下靠换行与滚动容纳）。
const double kFloatBaseFontSize = 12.5;

/// 图标按钮边长（逻辑像素，随 fontScale 缩放）。
double floatIconButtonSize(double fontScale) =>
    (27 * fontScale).clamp(20.0, 44.0);

/// 布局一帧。**纯函数**：同样的 (model, width, height) 必得同样的图元列表。
FloatFrame layoutFloatWindow(
  FloatWindowModel m, {
  required double width,
  required double height,
}) {
  final s = m.fontScale;
  final fs = kFloatBaseFontSize * s;
  final pad = 8.0 * s;
  final gap = 5.0 * s;
  final nodes = <FloatNode>[];
  final p = m.palette;

  // 整窗底（圆角交给画布裁剪）。
  nodes.add(FloatNode(
    kind: FloatNodeKind.box,
    rect: Rect.fromLTWH(0, 0, width, height),
    argb: p.background,
  ));

  // ---------------- 顶部第一栏（图标按钮，只有这里能拖窗口） ----------------
  // 左侧：识别序号（上）与日期时间（下）。M34 第 2 条：**不再显示**
  // 「共 N 题 / N 张图片」（信息价值低，还占掉半边标题栏）。
  final headTop = pad;
  final titleStyle = _style(fs * 1.02, p.text, 600);
  final subStyle = _style(fs * 0.82, p.subtext, 400);

  final line1 = '第 ${m.humanIndex}/${m.total} 次识别';
  final line2 = _formatTime(m.createdAt);
  final t1 = _measure(line1, titleStyle, maxWidth: width * 0.6);
  final t2 = _measure(line2, subStyle, maxWidth: width * 0.6);
  nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(pad, headTop, t1.width, t1.height),
      text: line1,
      fontSize: fs * 1.02,
      argb: p.text,
      weight: 600));
  nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(pad, headTop + t1.height + 1, t2.width, t2.height),
      text: line2,
      fontSize: fs * 0.82,
      argb: p.subtext));

  final btn = floatIconButtonSize(s);
  // M34 第 3 条：下一条 / 上一条**位置互换**（列表第一个画在最右边）。
  // M34 第 7 条：删掉顶部两个字号按钮（字号统一在设置页里调）。
  final buttons = <_IconBtn>[
    _IconBtn(FloatAction.next, Icons.chevron_right, '下一条',
        enabled: m.index > 0),
    _IconBtn(FloatAction.prev, Icons.chevron_left, '上一条',
        enabled: m.index < m.total - 1),
    _IconBtn(FloatAction.regenerate, Icons.refresh, '重新识别',
        enabled: !m.busy && m.total > 0),
    // M43 第 1 条：极简模式就是**默认模式**，另一个模式叫「详细解析模式」。
    _IconBtn(FloatAction.toggleMinimal,
        m.minimal ? Icons.expand : Icons.compress,
        m.minimal
            ? '切换到详细解析模式（选项全列 + 解析 + 材料）'
            : '切换到默认模式（只看题目与答案）',
        active: m.minimal),
    _IconBtn(FloatAction.toggleLock,
        m.locked ? Icons.lock_outline : Icons.lock_open_outlined,
        m.locked ? '解锁位置' : '锁定位置',
        active: m.locked),
  ];

  // 图标按钮排成一行、放不下就换行；整排按**右对齐**放（放不下时从下一行左起）。
  double bx = width - pad - btn;
  double by = headTop;
  final leftBlockRight = pad + (t1.width > t2.width ? t1.width : t2.width) + 6 * s;
  for (var i = 0; i < buttons.length; i++) {
    final b = buttons[i];
    if (bx < leftBlockRight && i > 0) {
      // 换行：从右边重新开始，整排下移。
      by += btn + gap;
      bx = width - pad - btn;
    }
    final r = Rect.fromLTWH(bx, by, btn, btn);
    nodes.add(FloatNode(
      kind: FloatNodeKind.box,
      rect: r,
      id: b.id,
      argb: b.active ? p.buttonActive : p.button,
      enabled: b.enabled,
      radius: 8 * s,
    ));
    // 图标字形**垂直居中**：只按 rect.top 画会让字形贴在按钮上沿
    // （M34 用户反馈「按钮文字异常」——像素复核确认偏移了半个行高）。
    final glyph = String.fromCharCode(b.icon.codePoint);
    final glyphTp = floatParagraph(
      glyph,
      _style(btn * 0.58, b.enabled ? p.text : p.subtext, 400,
          fontFamily: b.icon.fontFamily),
      maxWidth: btn,
      maxLines: 1,
      align: TextAlign.center,
    );
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(
          r.left, r.top + (btn - glyphTp.height) / 2, btn, glyphTp.height),
      text: glyph,
      fontFamily: b.icon.fontFamily,
      fontSize: btn * 0.58,
      argb: b.enabled ? p.text : p.subtext,
      align: TextAlign.center,
      painter: glyphTp,
    ));
    bx -= btn + gap;
  }

  final headerHeight = by + btn + pad;
  // 头部底色（插到最前面，压住文字下面的底色）。
  nodes.add(FloatNode(
    kind: FloatNodeKind.box,
    rect: Rect.fromLTWH(0, 0, width, headerHeight),
    argb: p.header,
  ));
  final headerBg = nodes.removeLast();
  nodes.insert(1, headerBg);
  nodes.add(FloatNode(
    kind: FloatNodeKind.box,
    rect: Rect.fromLTWH(0, headerHeight - 1, width, 1),
    argb: p.border,
  ));

  // ---------------- 底部两个识别按钮 ----------------
  // M33 第 5 条：识别中也照样可点。M34 先试过 macOS Dock 那样的悬停放大，
  // 用户看了一轮反馈「太奇怪」，撤掉；同时要求**按钮不要太大**（适度即可），
  // 所以这里用「一行文字那么高 + 上下留白」的紧凑尺寸，不做大块头；
  // 圆角与间距沿用主界面的 `AppRadius.control`，别让它的边看着「不像这个软件」。
  final footPad = pad;
  final footGap = pad;
  final footBtn = (fs * 1.9).clamp(18.0, 34.0);
  final footerH = footBtn + footPad * 2;
  final footerTop = height - footerH;
  final bodyRect = Rect.fromLTWH(pad * 0.6, headerHeight + gap,
      width - pad * 1.2, footerTop - headerHeight - gap * 2);

  final footer = <_IconBtn>[];
  final labels = <String>[];
  if (m.multiPage) {
    final full = m.stagedCount >= m.multiPageLimit;
    footer.add(_IconBtn(FloatAction.finishMulti, Icons.cloud_upload_outlined,
        '结束多页识别并上传',
        enabled: m.stagedCount > 0));
    footer.add(_IconBtn(FloatAction.addPage, Icons.add_photo_alternate_outlined,
        full ? '已达上限 ${m.multiPageLimit} 页' : '继续添加页面（${m.stagedCount}/${m.multiPageLimit}）',
        enabled: !full));
    footer.add(_IconBtn(FloatAction.cancelMulti, Icons.close, '取消多页'));
    labels.addAll(
        ['结束并上传', full ? '已达上限' : '继续添加页（${m.stagedCount}/${m.multiPageLimit}）', '取消多页']);
  } else {
    footer.add(_IconBtn(FloatAction.capture, Icons.center_focus_strong, '识别一张'));
    footer.add(_IconBtn(FloatAction.multiPage, Icons.filter_none, '多页识别'));
    labels.addAll(['识别一张', '多页识别']);
    // M43 第 2 条：默认模式（极简）多一个「复制识别内容」，排在**三个按钮的最后一个**。
    if (m.minimal) {
      footer.add(
          _IconBtn(FloatAction.copyContent, Icons.content_copy, '复制识别内容'));
      labels.add('复制识别内容');
    }
  }

  final slotW =
      (width - pad * 2 - footGap * (footer.length - 1)) / footer.length;
  for (var i = 0; i < footer.length; i++) {
    final b = footer[i];
    final r = Rect.fromLTWH(
        pad + i * (slotW + footGap), footerTop + footPad, slotW, footBtn);
    nodes.add(FloatNode(
      kind: FloatNodeKind.box,
      rect: r,
      id: b.id,
      argb: p.accent,
      enabled: b.enabled,
      radius: AppRadius.control * s,
    ));
    // 标签**垂直居中**（用户反馈「按钮文字异常」就是这里贴了上沿）。
    final labelColor = b.enabled ? 0xFFFFFFFF : p.subtext;
    final labelTp = floatParagraph(
      labels[i],
      _style(fs * 0.84, labelColor, 600),
      maxWidth: slotW,
      maxLines: 1,
      align: TextAlign.center,
    );
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(r.left, r.top + (footBtn - labelTp.height) / 2,
          slotW, labelTp.height),
      text: labels[i],
      fontSize: fs * 0.84,
      argb: labelColor,
      weight: 600,
      align: TextAlign.center,
      painter: labelTp,
    ));
  }

  // ---------------- 内容区（内容坐标系 → 平移到内容区左上角） ----------------
  final contentH = m.contentHeight;
  final scrollMax =
      (contentH - bodyRect.height).clamp(0.0, double.infinity).toDouble();
  final delta = Offset(bodyRect.left, bodyRect.top);
  for (final n in m.content) {
    nodes.add(n.intoBody(delta));
  }
  if (m.content.isEmpty) {
    final t = _measure(m.emptyText, _style(fs, p.subtext, 400),
        maxWidth: bodyRect.width, maxLines: 6);
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(
          bodyRect.left, bodyRect.top + 12 * s, bodyRect.width, t.height),
      text: m.emptyText,
      fontSize: fs,
      argb: p.subtext,
      inBody: true,
      maxLines: 6,
      align: TextAlign.center,
    ));
  }
  if (m.contentFailed) {
    const failedText = '内容渲染失败：请到主窗口查看这次识别的题目';
    final t = _measure(failedText, _style(fs, p.text, 500),
        maxWidth: bodyRect.width, maxLines: 4);
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(
          bodyRect.left, bodyRect.top + 12 * s, bodyRect.width, t.height),
      text: failedText,
      fontSize: fs,
      argb: p.text,
      inBody: true,
      maxLines: 4,
      align: TextAlign.center,
    ));
  }

  // ---------------- 一次性提示（复制结果，M42） ----------------
  final tipText = m.tipText;
  if (tipText != null && tipText.isNotEmpty) {
    final tipStyle = _style(fs * 0.88, 0xFFFFFFFF, 600);
    final tt = _measure(tipText, tipStyle, maxWidth: bodyRect.width * 0.9);
    final tw = tt.width + 20 * s;
    final th = tt.height + 12 * s;
    final left = (bodyRect.center.dx - tw / 2)
        .clamp(2.0, (width - tw - 2).clamp(2.0, width));
    // 识别中时把这条提示抬到横幅上面，别互相压住。
    final top = bodyRect.bottom - th - (m.busy ? 56 * s : 10 * s);
    nodes.add(FloatNode(
      kind: FloatNodeKind.box,
      rect: Rect.fromLTWH(left, top, tw, th),
      argb: Color(p.tooltip).withValues(alpha: 0.94).toARGB32(),
      radius: 6 * s,
      overlay: true,
    ));
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(left, top + 6 * s, tw, tt.height),
      text: tipText,
      fontSize: fs * 0.88,
      argb: 0xFFFFFFFF,
      weight: 600,
      maxLines: 1,
      align: TextAlign.center,
      overlay: true,
    ));
  }

  // ---------------- 识别中提示（贴在内容区**下部**） ----------------
  if (m.busy) {
    final bannerW = (bodyRect.width * 0.94).clamp(80.0, bodyRect.width);
    final bt = _measure(m.busyText, _style(fs * 0.95, p.text, 600),
        maxWidth: bannerW - 16 * s, maxLines: 2);
    final bannerH = bt.height + 14 * s;
    final banner = Rect.fromLTWH(
      bodyRect.center.dx - bannerW / 2,
      bodyRect.bottom - bannerH - 6 * s,
      bannerW,
      bannerH,
    );
    nodes.add(FloatNode(
      kind: FloatNodeKind.box,
      rect: banner,
      argb: Color(p.tooltip).withValues(alpha: 0.92).toARGB32(),
      radius: 8 * s,
      overlay: true,
    ));
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(banner.left + 8 * s, banner.top + 7 * s,
          banner.width - 16 * s, bt.height),
      text: m.busyText,
      fontSize: fs * 0.95,
      argb: 0xFFFFFFFF,
      weight: 600,
      maxLines: 2,
      align: TextAlign.center,
      overlay: true,
    ));
  }

  // ---------------- 悬停提示（图标按钮的名称） ----------------
  final hoveredIdx = buttons.indexWhere((b) => b.id == m.hoveredId);
  if (hoveredIdx >= 0) {
    final hovered = buttons[hoveredIdx];
    final tipStyle = _style(fs * 0.82, 0xFFFFFFFF, 500);
    final tt = _measure(hovered.tip, tipStyle, maxWidth: width * 0.7);
    final tw = tt.width + 14 * s;
    final th = tt.height + 8 * s;
    // 从已经画出来的图元里找这个按钮的实际矩形。
    final box = nodes.lastWhere(
        (n) => n.id == m.hoveredId && n.kind == FloatNodeKind.box);
    final left = (box.rect.center.dx - tw / 2)
        .clamp(2.0, (width - tw - 2).clamp(2.0, width));
    final top = box.rect.bottom + 4 * s;
    nodes.add(FloatNode(
      kind: FloatNodeKind.box,
      rect: Rect.fromLTWH(left, top, tw, th),
      argb: p.tooltip,
      radius: 5 * s,
      overlay: true,
    ));
    nodes.add(FloatNode(
      kind: FloatNodeKind.text,
      rect: Rect.fromLTWH(left, top + 4 * s, tw, tt.height),
      text: hovered.tip,
      fontSize: fs * 0.82,
      argb: 0xFFFFFFFF,
      maxLines: 1,
      align: TextAlign.center,
      overlay: true,
    ));
  }

  return FloatFrame(
    nodes: nodes,
    bodyRect: bodyRect,
    headerRect: Rect.fromLTWH(0, 0, width, headerHeight),
    scrollMax: scrollMax,
    width: width,
    height: height,
    contentHeight: contentH,
  );
}

/// `rawRgba`（**预乘** alpha）→ 预乘 BGRA（`UpdateLayeredWindow` 要的字节序），
/// 顺便把整窗透明度乘进去（乘在像素里比交给 DWM 稳，见 M36/M38）。
///
/// 抽出来是为了让「富文本渲染」（`float_window_rich.dart`）与这里的图元渲染
/// 走**同一份**转换：公式/化学式/表格那套是引擎出的 RGBA，图元那套也是。
Uint8List premultipliedBgra(Uint8List src, double opacity) {
  final out = Uint8List(src.length);
  final a = opacity.clamp(0.0, 1.0);
  if (a >= 1.0) {
    for (var i = 0; i + 3 < out.length; i += 4) {
      out[i] = src[i + 2];
      out[i + 1] = src[i + 1];
      out[i + 2] = src[i];
      out[i + 3] = src[i + 3];
    }
    return out;
  }
  for (var i = 0; i + 3 < out.length; i += 4) {
    out[i] = (src[i + 2] * a).round();
    out[i + 1] = (src[i + 1] * a).round();
    out[i + 2] = (src[i] * a).round();
    out[i + 3] = (src[i + 3] * a).round();
  }
  return out;
}

/// 把**一块**图元画成一张位图（预乘 alpha 的 BGRA，`UpdateLayeredWindow` 要的格式）。
///
/// M36：这是分块缓存的出图入口。窗口外观 / 内容 / 浮层各出一张图（**只在它们变化时**），
/// 之后每帧只由 `float_window_compose.dart` 在 Dart 里做 memcpy 合成 ——
/// 原来每帧都要跑一次 `Picture.toImage` + 4 MB 读回（实测 ~40 ms，用户报「很卡」）。
///
/// [origin] 是这张位图左上角在**窗口坐标系**里的位置（内容图的 origin 就是内容区左上角）；
/// [backgroundArgb] 非 0 时先用它铺底（不透明底图合成时可以直接整行 memcpy）；
/// [cornerRadius] > 0 时按窗口圆角裁剪（只有外观块需要，它铺满整窗）；
/// [opacity] < 1 时在这里把透明度**乘进像素**（每块只乘一次，比每帧交给 DWM 快得多）。
Future<Uint8List> renderNodes(
  List<FloatNode> nodes, {
  required double width,
  required double height,
  required double devicePixelRatio,
  Offset origin = Offset.zero,
  int backgroundArgb = 0,
  double cornerRadius = 0,
  double opacity = 1,
}) async {
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final pw = (width * dpr).round().clamp(1, 8192);
  final ph = (height * dpr).round().clamp(1, 8192);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);
  canvas.translate(-origin.dx, -origin.dy);
  if (cornerRadius > 0) {
    canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, width, height),
        Radius.circular(cornerRadius)));
  }
  if (backgroundArgb != 0) {
    canvas.drawRect(Rect.fromLTWH(origin.dx, origin.dy, width, height),
        Paint()..color = Color(backgroundArgb));
  }

  for (final node in nodes) {
    if (node.kind == FloatNodeKind.box) {
      final rrect =
          RRect.fromRectAndRadius(node.rect, Radius.circular(node.radius));
      canvas.drawRRect(rrect, Paint()..color = Color(node.argb));
      final border = node.borderArgb;
      if (border != null && node.borderWidth > 0) {
        canvas.drawRRect(
            rrect.deflate(node.borderWidth / 2),
            Paint()
              ..color = Color(border)
              ..style = PaintingStyle.stroke
              ..strokeWidth = node.borderWidth);
      }
      continue;
    }
    final painter = node.painter ??
        floatParagraph(
          node.text ?? '',
          _style(node.fontSize, node.argb, node.weight,
              fontFamily: node.fontFamily),
          maxWidth: node.rect.width,
          maxLines: node.maxLines,
          align: node.align,
        );
    final dx = node.align == TextAlign.center
        ? node.rect.left + (node.rect.width - painter.width) / 2
        : node.rect.left;
    painter.paint(canvas, Offset(dx, node.rect.top));
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pw, ph);
  // `rawRgba` 是**预乘 alpha** 的（`rawStraightRgba` 还要引擎在 CPU 上反预乘一遍）。
  // 预乘 + 通道序换成 BGRA 正好是 `UpdateLayeredWindow` 要的语义。
  // 窗口透明度**不在这里乘** —— 走原生层的 `BLENDFUNCTION.SourceConstantAlpha`。
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('悬浮窗渲染失败：拿不到像素数据');

  final src = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  // 换通道序 + 乘整窗透明度：与富文本渲染共用同一份实现。
  final out = premultipliedBgra(src, opacity);
  if (out.length == pw * ph * 4) return out;
  final fixed = Uint8List(pw * ph * 4)..setRange(0, out.length, out);
  return fixed;
}

// ---------------------------------------------------------------------------
// 内部工具
// ---------------------------------------------------------------------------

class _IconBtn {
  const _IconBtn(this.id, this.icon, this.tip,
      {this.enabled = true, this.active = false});
  final String id;
  final IconData icon;
  final String tip;
  final bool enabled;
  final bool active;
}

TextStyle _style(double size, int argb, int weight, {String? fontFamily}) =>
    TextStyle(
      fontSize: size,
      color: Color(argb),
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      fontFamily: fontFamily ?? 'MiSans',
      fontFamilyFallback:
          fontFamily == null ? const ['Microsoft YaHei UI', 'Segoe UI'] : null,
      height: 1.25,
    );

Size _measure(String text, TextStyle style,
    {double maxWidth = double.infinity, int maxLines = 1}) {
  final tp = floatParagraph(text, style,
      maxWidth: maxWidth, maxLines: maxLines, align: TextAlign.left);
  return Size(tp.width, tp.height);
}

/// 排一段文本。**公开**给内容层复用（内容层把排好的 [TextPainter] 挂在
/// `FloatNode.painter` 上缓存，渲染时不再重新排版）。
///
/// `maxLines <= 0` = 不限行数（内容层的题干/解析要能整段换行）。
TextPainter floatParagraph(
  String text,
  TextStyle style, {
  required double maxWidth,
  int maxLines = 1,
  TextAlign align = TextAlign.left,
}) {
  final unlimited = maxLines <= 0;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: unlimited ? null : maxLines,
    ellipsis: unlimited || maxLines > 1 ? null : '…',
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
  return tp;
}

/// 排一段**带样式片段的**文本（M42：极简面板一题一个段落，题号/题型/答案各自
/// 换色换字重，但仍然是**同一个 `TextPainter`** —— 拖选要按字符下标取值，
/// 拆成多个图元会让跨行选区的下标错位）。
TextPainter floatParagraphSpan(
  InlineSpan span, {
  required double maxWidth,
  TextAlign align = TextAlign.left,
}) {
  return TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
}

/// `2026-09-21 14:03`（不引 intl：只需要这一个格式）。
String _formatTime(int ms) {
  if (ms <= 0) return '—';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
