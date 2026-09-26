/// 悬浮窗的**分块缓存 + CPU 合成**（M36 起；M38 加同步快路径与多份缓存）。
///
/// 背景：M34/M35 时每一帧都要走一遍「`PictureRecorder` → `Picture.toImage` →
/// 4 MB 像素读回 → 换通道」，实测约 40 ms（用户报「悬浮窗很卡」）。而绝大多数帧
/// 只改了一点点东西（滚动、鼠标悬停），整窗重画纯属浪费。
///
/// 做法：把一帧拆成三块，各自**只在内容变化时**出图并缓存，其余每帧只在 Dart 里做
/// 内存拷贝 / 叠加（实测 1 ms 量级）：
///
/// | 块 | 内容 | 变化时机 |
/// |---|---|---|
/// | chrome | 整窗外观（底色、顶部第一栏、底部按钮），不透明底、带窗口圆角 | 改外观/明暗/配色/字号、翻记录、多页状态 |
/// | content | 内容区整篇（已铺不透明底），宽 = 内容区宽、高 = 内容总高 | 新识别结果、切极简、改字号 |
/// | overlay | 浮层小图（识别中提示 / 悬停提示），带 alpha | 悬停按钮、识别开始/结束 |
///
/// **两条路径**（M38）：
/// - [composeFast]：三块都命中缓存时**同步**合成（滚动、悬停帧走这条，不产生 Future、
///   不进微任务队列）；
/// - [compose]：需要重新出图时才走（内容是新的、外观变了），异步等 `toImage`。
///
/// 整窗透明度在这里乘进像素（每块只乘一次，指纹带 opacity），**不交给 DWM 的
/// `SourceConstantAlpha`** —— 实测那样会让滚动卡到不能用。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset, Rect;

import 'float_window_view.dart';

/// 内容片的**富文本渲染器**（M40）：把「内容坐标 [tileTop, tileTop+tileHeight)」那一段
/// 用主界面同一套 `QuestionCard` 离屏渲成位图（公式/化学式/表格与主界面一致）。
typedef FloatContentTileRenderer = Future<Uint8List> Function({
  required double width,
  required double tileTop,
  required double tileHeight,
  required double devicePixelRatio,

  /// 内容区底色（不透明）：必须由渲染器铺满，否则分层窗口的透明像素会露出桌面。
  required int backgroundArgb,
  double opacity,
});

/// 把一块图元画成一张位图（默认就是 [renderNodes]；单测塞假实现以避开 `toImage`）。
typedef FloatPieceRenderer = Future<Uint8List> Function(
  List<FloatNode> nodes, {
  required double width,
  required double height,
  required double devicePixelRatio,
  Offset origin,
  int backgroundArgb,
  double cornerRadius,
  double opacity,
});

/// 合成结果。
///
/// ⚠️ [pixels] 是**合成器内部复用的缓冲**（为了不每帧新建 4 MB）：只在「下一次
/// `compose` / `composeFast` 之前」有效；要留着它就得自己拷一份。原生 `setFrame`
/// 是在本次调用里同步拷进 DIB 的，所以直接用没问题。
class ComposeResult {
  const ComposeResult({
    required this.pixels,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.chromeRendered,
    required this.contentRendered,
    required this.overlayRendered,
  });

  final Uint8List pixels;
  final int pixelWidth;
  final int pixelHeight;

  /// 本次是否重新出了图（true = 走了引擎；false = 纯合成）。
  final bool chromeRendered;
  final bool contentRendered;
  final bool overlayRendered;

  /// 是否**完全**没出图（纯合成帧）—— 滚动 / 悬停就应该是这种帧。
  bool get compositeOnly =>
      !chromeRendered && !contentRendered && !overlayRendered;
}

/// 一帧拆出来的三块 + 浮层矩形。
class _Parts {
  const _Parts({
    required this.chrome,
    required this.content,
    required this.overlay,
    required this.overlayRect,
    required this.contentHeight,
    required this.cardBackground,
  });

  final List<FloatNode> chrome;
  final List<FloatNode> content;
  final List<FloatNode> overlay;
  final Rect? overlayRect;
  final double contentHeight;

  /// 出图时要先铺的底色（内容/外观块都要，才能整行 memcpy 合成）。
  final int cardBackground;
}

/// 三块的指纹 + 整帧指纹。
class _Keys {
  const _Keys({
    required this.chrome,
    required this.content,
    required this.overlay,
    required this.frame,
    required this.pw,
    required this.ph,
  });

  final int chrome;
  final int content;
  final int overlay;
  final int frame;
  final int pw;
  final int ph;
}

class _Piece {
  _Piece({
    required this.key,
    required this.pixels,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.origin,
  });

  final int key;
  final Uint8List pixels;
  final int pixelWidth;
  final int pixelHeight;
  final Offset origin;
}

/// 一种块的**小缓存**。
///
/// 为什么必须留多份：极简 / 锁定 这类顶部按钮是**来回切**的，只留一个槽位时两个
/// 指纹会互相顶掉 —— 实测每点一次就要重出整张内容图（665×8192 ≈ 22 MB），
/// 30 轮点击出了 192 张图、RSS 冲到 789 MB，单帧 0.3–1.3 s。用户报的
/// 「频繁点上面按钮就崩溃」正是这条分配风暴（M38）。
///
/// 容量按块给（用户能同时翻的**状态组合数**）：
/// - 外观块：`极简 × 锁定` = 4 种，留 4；
/// - 内容块：只有「正常 / 极简」两套（锁定不影响内容），留 2 —— 它一张就 22 MB；
/// - 浮层块：5 个顶部按钮的提示 + 识别中提示，留 6（张张都很小）。
class _PieceCache {
  _PieceCache(this.capacity, {this.byteBudgetMb = 0});

  final int capacity;

  /// 缓存占用的**字节**上限（MB，0 = 不限）。
  ///
  /// M47：光有条数上限不够 —— 3.0× 比例 + DPR2 时一张外观块就 37 MB，
  /// 「留 4 份」能到 150 MB，加内容片最坏 ~330 MB（SPEC §9 的内存指标）。
  /// 超预算时从最旧的开始丢（最近用到的留着，命中率不受影响）。
  final int byteBudgetMb;

  final List<_Piece> _items = [];

  int get bytes => _items.fold(0, (sum, p) => sum + p.pixels.length);

  _Piece? operator [](int key) {
    for (final p in _items) {
      if (p.key == key) return p;
    }
    return null;
  }

  void put(_Piece piece) {
    _items.removeWhere((p) => p.key == piece.key);
    _items.add(piece);
    final budget = byteBudgetMb * 1024 * 1024;
    while (_items.length > capacity ||
        (budget > 0 && bytes > budget && _items.length > 1)) {
      _items.removeAt(0); // 丢最旧的（**不 dispose**：Dart 侧只有字节，交给 GC）
    }
  }

  void clear() => _items.clear();

  /// 排障用：当前缓存里的位图尺寸。
  String describe() => _items.isEmpty
      ? '无'
      : _items.map((p) => '${p.pixelWidth}x${p.pixelHeight}').join('+');
}

/// 内容区**切片高度**（逻辑像素）。
///
/// 为什么要切片（M39，用户报「悬浮窗在默认模式下显示不全被截断」）：
/// 一块位图的高度是被 `clamp(1, 8192)` **物理像素**卡死的，而内容可以很长 ——
/// 实测一份 20 题的识别结果内容高 **4659 逻辑像素**，DPR2 就是 9318 物理像素，
/// 整块出图会被截到 8192，于是滚到底部时最后 563 逻辑像素（约两题）永远看不见、
/// 底下是一片底色。切片之后高度不再有上限：按需出的片数只与「内容多长」有关，
/// 而每帧真正需要的只有可见区覆盖的那 1–2 片（读一片是 2048 物理像素高，
/// 比原来那张 8192 的整图快得多，首屏出图也从 650–780 ms 降到 ~150–300 ms）。
const double kFloatContentTileHeight = 1024;

/// 选中高亮的混色强度（M42）：主色按它叠在内容上（`0.32` 与系统里的选中底接近，
/// 底下的字仍然看得清）。
const int kFloatSelectionAlpha = 82;

/// 分块缓存 + 合成器。
class FloatFrameComposer {
  FloatFrameComposer({
    FloatPieceRenderer? renderPiece,
    this.renderContentTile,
    this.contentChunkHeight = kFloatContentTileHeight,
  }) : renderPiece = renderPiece ?? renderNodes;

  /// 内容切片高度（逻辑像素）。图元直排（便宜）用小片提高命中率；
  /// **富文本渲染（贵）用大片**（见 [renderContentTile]）：一片要重跑一遍 widget
  /// 管线，片太小就会「每滚十几格重跑一次」→ 滚动卡（M40 用户实测）。
  final double contentChunkHeight;

  final FloatPieceRenderer renderPiece;

  /// 内容片用富文本渲染（M40）；null = 退回图元直排（老路径/单测）。
  final FloatContentTileRenderer? renderContentTile;

  /// 每种块留几份（M38）：见 [_PieceCache] 的说明 —— 来回切极简/锁定时不再重出图。
  /// 后面的 MB 是 M47 加的**字节**上限（大比例 × 高 DPR 时条数封顶不管用）。
  final _chromeCache = _PieceCache(4, byteBudgetMb: 48);

  /// 内容区的**切片**缓存（M39）：键 = 内容指纹 ^ 片号。留 8 片
  /// （1024 逻辑像素/片，DPR2 下一片约 5 MB）≈ 40 MB，够覆盖
  /// 「正常 / 极简两套内容 + 相邻要滚到的片」；3.0× 比例时一片 16 MB 以上，
  /// 所以再给一条 96 MB 的字节上限（M47）。
  final _tileCache = _PieceCache(8, byteBudgetMb: 96);
  final _overlayCache = _PieceCache(6, byteBudgetMb: 12);

  /// 上一次合成的完整签名（一样就直接复用上一帧像素，连合成都省）。
  int? _lastFrameKey;
  Uint8List? _lastPixels;
  int _lastPw = 0;
  int _lastPh = 0;

  /// 复用的输出缓冲（每帧新建 4 MB 会喂给 GC）。
  Uint8List? _out;

  /// 统计（日志/测试用）：出图次数 / 合成帧数。
  int pieceRenders = 0;
  int compositeFrames = 0;

  /// 最近一帧的分段耗时（微秒），排障用。
  int lastSplitUs = 0;
  int lastKeysUs = 0;
  int lastRenderUs = 0;
  int lastCopyUs = 0;
  int lastOverlayUs = 0;
  int lastCornerUs = 0;
  int lastTotalUs = 0;

  void dispose() {
    _chromeCache.clear();
    _tileCache.clear();
    _overlayCache.clear();
    _lastFrameKey = null;
    _lastPixels = null;
    _out = null;
  }

  // ------------------------------------------------------------- 同步快路径
  /// 三块都命中缓存时**同步**合成；需要出图时返回 null（调用方走 [compose]）。
  ComposeResult? composeFast({
    required FloatFrame frame,
    required FloatWindowPalette palette,
    required double devicePixelRatio,
    required double scrollPx,
    double opacity = 1,
    double cornerRadius = 0,
    int contentSignature = 0,
    List<Rect> selectionRects = const [],
    int selectionArgb = 0,
  }) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final parts = _split(frame, palette);
    final keys = _keys(parts, frame,
        dpr: dpr,
        opacity: opacity,
        cornerRadius: cornerRadius,
        contentSignature: contentSignature,
        selectionKey: selectionKeyOf(selectionRects, selectionArgb));
    final overlayCached = parts.overlayRect == null
        ? true
        : _overlayCache[keys.overlay] != null;
    if (_chromeCache[keys.chrome] == null ||
        !_tilesReady(parts, frame, dpr, scrollPx, keys.content) ||
        !overlayCached) {
      return null;
    }
    return _finish(parts, frame, dpr, scrollPx, keys, cornerRadius,
        chromeRendered: false,
        contentRendered: false,
        overlayRendered: false,
        selectionRects: selectionRects,
        selectionArgb: selectionArgb);
  }

  // --------------------------------------------------------------- 异步路径
  /// 合成一帧（必要时先出图）。[scrollPx] 是内容区滚动量（逻辑像素，>0 = 内容上移）。
  Future<ComposeResult> compose({
    required FloatFrame frame,
    required FloatWindowPalette palette,
    required double devicePixelRatio,
    required double scrollPx,
    double opacity = 1,
    double cornerRadius = 0,
    int contentSignature = 0,
    List<Rect> selectionRects = const [],
    int selectionArgb = 0,
  }) async {
    final sw = Stopwatch()..start();
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final parts = _split(frame, palette);
    lastSplitUs = sw.elapsedMicroseconds;
    final keys = _keys(parts, frame,
        dpr: dpr,
        opacity: opacity,
        cornerRadius: cornerRadius,
        contentSignature: contentSignature,
        selectionKey: selectionKeyOf(selectionRects, selectionArgb));
    lastKeysUs = sw.elapsedMicroseconds;

    var chromeRendered = false;
    var contentRendered = false;
    var overlayRendered = false;

    if (_chromeCache[keys.chrome] == null) {
      _chromeCache.put(_Piece(
        key: keys.chrome,
        pixels: await renderPiece(
          parts.chrome,
          width: frame.width,
          height: frame.height,
          devicePixelRatio: dpr,
          origin: Offset.zero,
          backgroundArgb: parts.cardBackground,
          cornerRadius: cornerRadius,
          opacity: opacity,
        ),
        pixelWidth: keys.pw,
        pixelHeight: keys.ph,
        origin: Offset.zero,
      ));
      pieceRenders++;
      chromeRendered = true;
    }
    // 内容按片出图：一帧只需要可见区覆盖的那 1–2 片，再往后带一片做预取
    // （用户滚下一屏时那一片已经在了）。
    final visible = _visibleTiles(parts, frame, dpr, scrollPx);
    final lastTile = _tileCount(parts, dpr) - 1;
    final want = <int>{
      for (var i = visible.first; i <= visible.last; i++) i,
      if (visible.last + 1 <= lastTile) visible.last + 1,
    };
    for (final i in want) {
      final key = _tileKey(keys.content, i);
      if (_tileCache[key] != null) continue;
      final top = i * contentChunkHeight;
      final h = math.min(contentChunkHeight, parts.contentHeight - top);
      if (h <= 0) continue;
      // ⚠ 原点必须是**窗口坐标**：`layoutFloatWindow` 已经把内容图元平移到了
      // `bodyRect.topLeft`（`n.intoBody(delta)`），所以第 i 片的位图左上角落在
      // `(bodyRect.left, bodyRect.top + i×片高)`。漏掉 `bodyRect.topLeft` 会让内容
      // 整体下移一个表头高、右移一个左边距 —— 表现就是用户报的「不顶头 / 底部被
      // 识别按钮压住 / 左右边距不对等」（M39 的 `⑭` 回归钉住这条）。
      final tileOrigin = Offset(
          frame.bodyRect.left, frame.bodyRect.top + top);
      final rich = renderContentTile;
      _tileCache.put(_Piece(
        key: key,
        pixels: rich != null
            ? await rich(
                width: frame.bodyRect.width,
                tileTop: top,
                tileHeight: h,
                devicePixelRatio: dpr,
                backgroundArgb: parts.cardBackground,
                opacity: opacity,
              )
            : await renderPiece(
                parts.content,
                width: frame.bodyRect.width,
                height: h,
                devicePixelRatio: dpr,
                origin: tileOrigin,
                backgroundArgb: parts.cardBackground,
                opacity: opacity,
              ),
        pixelWidth: (frame.bodyRect.width * dpr).round().clamp(1, 8192),
        pixelHeight: (h * dpr).round().clamp(1, 8192),
        origin: tileOrigin,
      ));
      pieceRenders++;
      if (i >= visible.first && i <= visible.last) contentRendered = true;
    }
    final overlayRect = parts.overlayRect;
    if (overlayRect != null && _overlayCache[keys.overlay] == null) {
      _overlayCache.put(_Piece(
        key: keys.overlay,
        pixels: await renderPiece(
          parts.overlay,
          width: overlayRect.width,
          height: overlayRect.height,
          devicePixelRatio: dpr,
          origin: overlayRect.topLeft,
          backgroundArgb: 0,
          opacity: opacity,
        ),
        pixelWidth: (overlayRect.width * dpr).round().clamp(1, 8192),
        pixelHeight: (overlayRect.height * dpr).round().clamp(1, 8192),
        origin: overlayRect.topLeft,
      ));
      pieceRenders++;
      overlayRendered = true;
    }
    lastRenderUs = sw.elapsedMicroseconds - lastKeysUs;
    return _finish(parts, frame, dpr, scrollPx, keys, cornerRadius,
        chromeRendered: chromeRendered,
        contentRendered: contentRendered,
        overlayRendered: overlayRendered,
        selectionRects: selectionRects,
        selectionArgb: selectionArgb,
        sw: sw);
  }

  // ------------------------------------------------------------------ 内部
  static _Parts _split(FloatFrame frame, FloatWindowPalette palette) {
    final chrome = <FloatNode>[];
    final content = <FloatNode>[];
    final overlay = <FloatNode>[];
    for (final n in frame.nodes) {
      if (n.overlay) {
        overlay.add(n);
      } else if (n.inBody) {
        content.add(n);
      } else {
        chrome.add(n);
      }
    }
    return _Parts(
      chrome: chrome,
      content: content,
      overlay: overlay,
      overlayRect: _overlayRect(overlay, frame),
      contentHeight: math.max(frame.contentHeight, frame.bodyRect.height),
      cardBackground: palette.background,
    );
  }

  static _Keys _keys(
    _Parts parts,
    FloatFrame frame, {
    required double dpr,
    required double opacity,
    required double cornerRadius,
    int contentSignature = 0,
    int selectionKey = 0,
  }) {
    final pw = (frame.width * dpr).round().clamp(1, 8192);
    final ph = (frame.height * dpr).round().clamp(1, 8192);
    final chromeKey = nodesKey(parts.chrome,
        width: frame.width,
        height: frame.height,
        background: parts.cardBackground,
        dpr: dpr,
        opacity: opacity);
    // 富文本渲染时内容区没有图元（内容是 widget 树），所以内容键靠
    // `contentSignature`（题目指纹 + 宽度/字号/配色/明暗）来区分。
    final contentKey = nodesKey(parts.content,
            width: frame.bodyRect.width,
            height: parts.contentHeight,
            background: parts.cardBackground,
            dpr: dpr,
            opacity: opacity) *
        31 +
        contentSignature;
    final overlayKey = parts.overlayRect == null
        ? 0
        : nodesKey(parts.overlay,
            width: parts.overlayRect!.width,
            height: parts.overlayRect!.height,
            dpr: dpr,
            opacity: opacity);
    var frameKey = chromeKey;
    frameKey = frameKey * 31 + contentKey;
    frameKey = frameKey * 31 + overlayKey;
    frameKey = frameKey * 31 + (parts.contentHeight * 10).round();
    frameKey = frameKey * 31 + (cornerRadius * 10).round();
    frameKey = frameKey * 31 + (opacity * 1000).round();
    frameKey = frameKey * 31 + pw;
    frameKey = frameKey * 31 + ph;
    // 选区也要进帧指纹（M42）：选区一变就得重合成，否则拖选时画面不动。
    return _Keys(
      chrome: chromeKey,
      content: contentKey,
      overlay: overlayKey,
      frame: frameKey * 31 + selectionKey,
      pw: pw,
      ph: ph,
    );
  }

  /// 选区的指纹（矩形集合 + 颜色）。
  static int selectionKeyOf(List<Rect> rects, int argb) {
    if (rects.isEmpty) return 0;
    var h = 0xcbf29ce484222325 ^ argb;
    for (final r in rects) {
      h ^= (r.left * 4).round() & 0xFFFFFFFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      h ^= (r.top * 4).round() & 0xFFFFFFFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      h ^= (r.width * 4).round() & 0xFFFFFFFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      h ^= (r.height * 4).round() & 0xFFFFFFFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h & 0x7FFFFFFFFFFFFFFF;
  }

  /// 真正把三块合成为一帧像素（**同步**）。
  ComposeResult _finish(
    _Parts parts,
    FloatFrame frame,
    double dpr,
    double scrollPx,
    _Keys keys,
    double cornerRadius, {
    required bool chromeRendered,
    required bool contentRendered,
    required bool overlayRendered,
    List<Rect> selectionRects = const [],
    int selectionArgb = 0,
    Stopwatch? sw,
  }) {
    final watch = sw ?? (Stopwatch()..start());
    // 滚动量单独进「帧指纹」：滚动帧要重合成，但不需要出图。
    final frameKey = keys.frame * 31 + (scrollPx * 10).round();
    final pw = keys.pw;
    final ph = keys.ph;

    final chrome = _chromeCache[keys.chrome];
    if (chrome == null || !_tilesReady(parts, frame, dpr, scrollPx, keys.content)) {
      // 缓存被换掉/账不对：这一帧没法合成（调用方会记日志），不要画出半张图。
      throw StateError('悬浮窗分块缓存缺块（chrome=${chrome == null} '
          'tiles=${!_tilesReady(parts, frame, dpr, scrollPx, keys.content)}）');
    }
    var out = _out;
    if (out == null || out.length != pw * ph * 4) {
      out = Uint8List(pw * ph * 4);
      _out = out;
      _lastFrameKey = null; // 缓冲换了，上一帧像素作废
    }
    final unchanged = frameKey == _lastFrameKey &&
        _lastPixels != null &&
        _lastPw == pw &&
        _lastPh == ph;
    if (unchanged) {
      lastTotalUs = watch.elapsedMicroseconds;
      return ComposeResult(
        pixels: _lastPixels!,
        pixelWidth: pw,
        pixelHeight: ph,
        chromeRendered: chromeRendered,
        contentRendered: contentRendered,
        overlayRendered: overlayRendered,
      );
    }

    out.setAll(0, chrome.pixels);
    final out32 = out.buffer.asUint32List();
    final bgWord = _bgraWord(parts.cardBackground);
    final bodyX = (frame.bodyRect.left * dpr).round().clamp(0, pw);
    final bodyY = (frame.bodyRect.top * dpr).round().clamp(0, ph);
    final bodyW = math.min(
        (frame.bodyRect.width * dpr).round(), (pw - bodyX).clamp(0, pw));
    final bodyH = (frame.bodyRect.height * dpr).round().clamp(0, ph - bodyY);
    final scrollPxPhysical =
        (scrollPx.clamp(0.0, double.infinity) * dpr).round();
    final tilePx = _tilePx(dpr);
    // 可见区按片整段拷贝：一片一片地对齐，每片一次连续 memcpy（不逐行 1140 次）。
    var row = 0;
    while (row < bodyH) {
      final dstRow = bodyY + row;
      final dst = dstRow * pw + bodyX;
      if (dstRow < 0 || dstRow >= ph || dst + bodyW > out32.length) break;
      final absRow = scrollPxPhysical + row;
      final tile = _tileCache[_tileKey(keys.content, absRow ~/ tilePx)];
      if (tile == null) {
        // 片没准备好：这一行（及之后）先铺底色，别画出错位的内容。
        out32.fillRange(dst, dst + bodyW, bgWord);
        row++;
        continue;
      }
      final inTile = absRow - (absRow ~/ tilePx) * tilePx;
      final rowPx = math.min(
          math.min(tilePx - inTile, bodyH - row), tile.pixelHeight - inTile);
      if (rowPx <= 0) {
        out32.fillRange(dst, dst + bodyW, bgWord);
        row++;
        continue;
      }
      final copyW = math.min(bodyW, tile.pixelWidth);
      final src = tile.pixels.buffer.asUint32List();
      if (copyW == bodyW && bodyW == pw - bodyX) {
        // 内容区正好铺满窗口剩下的整宽：一片一次连续 memcpy（省掉逐行 1140 次调用）。
        out32.setRange(
            dst, dst + rowPx * copyW, src, inTile * tile.pixelWidth);
      } else {
        // 两侧有留白时**必须逐行**：目标行距是窗口宽 pw，而被拷宽度是内容区宽 bodyW，
        // 当成一整块连续内存拷会每行漂移（pw - bodyW）像素 —— M39 的这条回归
        // （`⑫`）就是靠「底部一行必须是内容」抓出来的。
        for (var k = 0; k < rowPx; k++) {
          final d = (dstRow + k) * pw + bodyX;
          out32.setRange(
              d, d + copyW, src, (inTile + k) * tile.pixelWidth);
          if (copyW < bodyW) {
            out32.fillRange(d + copyW, d + bodyW, bgWord);
          }
        }
      }
      row += rowPx;
    }
    lastCopyUs = watch.elapsedMicroseconds -
        (sw == null ? 0 : lastRenderUs) -
        (sw == null ? lastKeysUs : 0);
    // 文本选区高亮（M42）：直接在合成好的像素上混色，不出图、不新建缓冲。
    _paintSelection(out32, pw, ph, selectionRects, selectionArgb,
        kFloatSelectionAlpha, dpr);
    final overlay = parts.overlayRect == null
        ? null
        : _overlayCache[keys.overlay];
    if (overlay != null) {
      _blend(out32, pw, ph, overlay, dpr);
    }
    // 圆角：M36 把整帧渲染拆块时漏了窗口圆角裁剪，这里在合成结果上补一次
    // （只动四个角那几小块像素）。外观块自己画的时候也按圆角裁过，两条路都覆盖。
    if (cornerRadius > 0) {
      _roundCorners(out32, pw, ph, (cornerRadius * dpr).round());
    }
    lastTotalUs = watch.elapsedMicroseconds;
    _lastFrameKey = frameKey;
    _lastPixels = out;
    _lastPw = pw;
    _lastPh = ph;
    compositeFrames++;
    return ComposeResult(
      pixels: out,
      pixelWidth: pw,
      pixelHeight: ph,
      chromeRendered: chromeRendered,
      contentRendered: contentRendered,
      overlayRendered: overlayRendered,
    );
  }

  /// 一片的高度（物理像素）。
  int _tilePx(double dpr) =>
      math.max(1, (contentChunkHeight * dpr).round());

  /// 内容一共要切成几片（至少 1 片）。
  int _tileCount(_Parts parts, double dpr) {
    if (parts.contentHeight <= 0) return 1;
    return (parts.contentHeight / contentChunkHeight).ceil().clamp(1, 1 << 20);
  }

  /// 内容指纹 + 片号 = 该片的缓存键。
  static int _tileKey(int contentKey, int index) =>
      (contentKey ^ (index * 0x9E3779B97F4A7C15)) & 0xFFFFFFFFFFFFFFFF;

  /// 当前可见区覆盖到的片号区间（含首含尾）。
  ({int first, int last}) _visibleTiles(
      _Parts parts, FloatFrame frame, double dpr, double scrollPx) {
    final tilePx = _tilePx(dpr);
    final last = _tileCount(parts, dpr) - 1;
    final start = (scrollPx.clamp(0.0, double.infinity) * dpr).round();
    final bodyH = (frame.bodyRect.height * dpr).round().clamp(0, 1 << 20);
    final end = math.max(start, start + bodyH - 1);
    return (
      first: (start ~/ tilePx).clamp(0, last),
      last: (end ~/ tilePx).clamp(0, last),
    );
  }

  /// 可见区要用的片是不是都在缓存里。
  bool _tilesReady(
      _Parts parts, FloatFrame frame, double dpr, double scrollPx, int key) {
    final v = _visibleTiles(parts, frame, dpr, scrollPx);
    for (var i = v.first; i <= v.last; i++) {
      if (_tileCache[_tileKey(key, i)] == null) return false;
    }
    return true;
  }

  /// 浮层小图覆盖的窗口内矩形（外扩 2 逻辑像素，夹在窗口里）。
  static Rect? _overlayRect(List<FloatNode> nodes, FloatFrame frame) {
    if (nodes.isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final n in nodes) {
      left = math.min(left, n.rect.left);
      top = math.min(top, n.rect.top);
      right = math.max(right, n.rect.right);
      bottom = math.max(bottom, n.rect.bottom);
    }
    final l = (left - 2).clamp(0.0, frame.width);
    final t = (top - 2).clamp(0.0, frame.height);
    final r = (right + 2).clamp(0.0, frame.width);
    final b = (bottom + 2).clamp(0.0, frame.height);
    if (r <= l || b <= t) return null;
    return Rect.fromLTRB(l, t, r, b);
  }

  /// 把四个角上「圆角之外」的像素清成透明。
  static void _roundCorners(Uint32List px, int pw, int ph, int radius) {
    if (radius <= 0) return;
    final r = math.min(radius, math.min(pw, ph) ~/ 2);
    if (r <= 0) return;
    final r2 = r * r;
    for (var y = 0; y < r; y++) {
      final dy = r - y - 0.5;
      final dx = math.sqrt(math.max(0.0, r2 - dy * dy));
      final inside = (r - dx).ceil();
      for (var x = 0; x < inside; x++) {
        px[y * pw + x] = 0;
        px[y * pw + (pw - 1 - x)] = 0;
        px[(ph - 1 - y) * pw + x] = 0;
        px[(ph - 1 - y) * pw + (pw - 1 - x)] = 0;
      }
    }
  }

  /// 预乘 BGRA 的一个像素字（小端 u32）= A<<24 | R<<16 | G<<8 | B。
  static int _bgraWord(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// 把**文本选区的高亮**直接调进合成好的像素（M42）。
  ///
  /// 为什么不去出一张「高亮浮层位图」：拖选时每一帧选区都在变，出图一次要
  /// `Picture.toImage` + 读回几十万个像素（几十毫秒），拖起来必然一格一格；
  /// 而选区高亮就是**若干轴对齐矩形**，直接在 `Uint32List` 上算一遍只要零点几毫秒。
  ///
  /// [rects] 是**窗口逻辑坐标**的矩形；颜色用主色（accent）按 [alpha] 混上去，
  /// 和系统里其它选中效果一致：底下的字仍然看得见。
  static void _paintSelection(
    Uint32List dst,
    int pw,
    int ph,
    List<Rect> rects,
    int argb,
    int alpha,
    double dpr,
  ) {
    if (rects.isEmpty || alpha <= 0) return;
    final a = alpha.clamp(0, 255);
    final inv = 255 - a;
    final sr = (argb >> 16) & 0xFF;
    final sg = (argb >> 8) & 0xFF;
    final sb = argb & 0xFF;
    for (final r in rects) {
      final x0 = (r.left * dpr).floor().clamp(0, pw);
      final x1 = (r.right * dpr).ceil().clamp(0, pw);
      final y0 = (r.top * dpr).floor().clamp(0, ph);
      final y1 = (r.bottom * dpr).ceil().clamp(0, ph);
      if (x1 <= x0 || y1 <= y0) continue;
      for (var y = y0; y < y1; y++) {
        final row = y * pw;
        for (var x = x0; x < x1; x++) {
          final d = dst[row + x];
          final b = (sb * a + (d & 0xFF) * inv) ~/ 255;
          final g = (sg * a + ((d >> 8) & 0xFF) * inv) ~/ 255;
          final rr = (sr * a + ((d >> 16) & 0xFF) * inv) ~/ 255;
          dst[row + x] = (0xFF << 24) | (rr << 16) | (g << 8) | b;
        }
      }
    }
  }

  /// 把带 alpha 的浮层小图 source-over 叠加到 [dst]（预乘 alpha 语义）。
  static void _blend(
    Uint32List dst,
    int pw,
    int ph,
    _Piece overlay,
    double dpr,
  ) {
    final src = overlay.pixels;
    final ox = (overlay.origin.dx * dpr).round();
    final oy = (overlay.origin.dy * dpr).round();
    for (var y = 0; y < overlay.pixelHeight; y++) {
      final dy = oy + y;
      if (dy < 0 || dy >= ph) continue;
      for (var x = 0; x < overlay.pixelWidth; x++) {
        final dx = ox + x;
        if (dx < 0 || dx >= pw) continue;
        final si = (y * overlay.pixelWidth + x) * 4;
        final sa = src[si + 3];
        if (sa == 0) continue;
        final di = dy * pw + dx;
        if (sa == 255) {
          dst[di] = (0xFF << 24) |
              (src[si + 2] << 16) |
              (src[si + 1] << 8) |
              src[si];
          continue;
        }
        final d = dst[di];
        final inv = 255 - sa;
        int mix(int s, int dv) => s + ((dv * inv) ~/ 255);
        final b = mix(src[si], d & 0xFF).clamp(0, 255);
        final g = mix(src[si + 1], (d >> 8) & 0xFF).clamp(0, 255);
        final r = mix(src[si + 2], (d >> 16) & 0xFF).clamp(0, 255);
        final a = (sa + (((d >> 24) & 0xFF) * inv) ~/ 255).clamp(0, 255);
        dst[di] = (a << 24) | (r << 16) | (g << 8) | b;
      }
    }
  }

  /// 一批图元的指纹：几何 + 颜色 + 文本内容（同一进程内稳定）。
  ///
  /// 用**整数哈希**而不是拼字符串：每帧都要为三块图元算一遍，字符串拼接在长内容下
  /// 是实打实的开销。**必须带上 DPR**：同一份图元在不同 DPR 下出的位图尺寸不同，
  /// 漏了它会在换显示器/改缩放后复用错尺寸的旧图（单测抓到的真 bug）。
  /// **必须带上透明度**：透明度是乘进像素的，不同透明度对应不同位图。
  static int nodesKey(
    List<FloatNode> nodes, {
    double width = 0,
    double height = 0,
    int background = 0,
    double dpr = 1,
    double opacity = 1,
  }) {
    var h = 0xcbf29ce484222325; // FNV-1a 64 起点
    int mix(int v) {
      h ^= v & 0xFFFFFFFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      return h;
    }

    mix((width * 10).round());
    mix((height * 10).round());
    mix(background);
    mix((dpr * 100).round());
    mix((opacity * 1000).round());
    mix(nodes.length);
    for (final n in nodes) {
      final r = n.rect;
      mix(n.kind.index);
      mix((r.left * 10).round());
      mix((r.top * 10).round());
      mix((r.width * 10).round());
      mix((r.height * 10).round());
      mix(n.argb);
      mix((n.radius * 10).round());
      mix(n.borderArgb ?? -1);
      mix((n.fontSize * 10).round());
      mix(n.weight);
      mix(n.align.index);
      mix(n.fontFamily?.hashCode ?? 0);
      mix(n.text?.hashCode ?? 0);
    }
    return h;
  }

  /// 供排障：当前缓存状态。
  String debugState() =>
      '（分块 ${(lastSplitUs / 1000).toStringAsFixed(1)}'
      ' · 指纹 ${((lastKeysUs - lastSplitUs) / 1000).toStringAsFixed(1)}'
      ' · 出图 ${(lastRenderUs / 1000).toStringAsFixed(1)}'
      ' · 拷贝 ${(lastCopyUs / 1000).toStringAsFixed(1)} ms）'
      'chrome=${_chromeCache.describe()}'
      ' content片=${_tileCache.describe()}'
      ' overlay=${_overlayCache.describe()}'
      ' 出图 $pieceRenders 次 / 合成 $compositeFrames 帧';
}
