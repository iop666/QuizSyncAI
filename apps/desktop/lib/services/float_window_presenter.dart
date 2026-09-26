import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show AppSettings, FloatWindowTheme;

import '../state/capture_coordinator.dart';
import 'float_window.dart';
import 'float_window_rich.dart';
import 'float_window_compose.dart';
import 'float_window_content.dart';
import 'float_window_selection.dart';
import 'float_window_view.dart';
import 'remote_task.dart';

/// 悬浮窗的「数据 + 动作 + 排版 + 合成」胶水（M32 / M33 / M34 / M36）。
///
/// 每次推帧做四件事：
/// 1. 取识别记录（时间倒序）与当前那次的题目（数据变化时）；
/// 2. `float_window_content.dart` 用 `TextPainter` 排版（缓存，命中不重排）；
/// 3. `float_window_view.dart` 的纯函数排窗口外观（第一栏 + 底部按钮 + 提示）；
/// 4. `FloatFrameComposer` 分块缓存 + CPU 合成出像素，交给原生分层窗口。
///
/// M36 的要点：**只有内容或外观变化时才出图**，滚动/悬停这类帧纯内存拷贝
/// （原来每帧都要 `Picture.toImage` + 4 MB 读回，约 40 ms，用户报「很卡」）。
class FloatWindowPresenter {
  FloatWindowPresenter({
    required this.window,
    required this.repo,
    required this.coordinator,
    required this.settings,
    required this.saveSettings,
    required this.appIsDark,
    required this.devicePixelRatioOf,
    required this.screenLogicalSizeOf,
    FloatFrameComposer? composer,
    FloatContentBuilder? contentBuilder,
    FloatRichMeasurer? measureRichContent,
    FloatRichTileRasterizer? rasterRichContent,

    /// 内容是否走「与主界面同源的富文本渲染」（公式/化学式/表格）。
    ///
    /// **默认关**：富文本一次出图 300–700 ms，只要它还在推帧链路上，滚动就一定会
    /// 被它拖住（连报三轮「卡的不行」）。先回到实测顺滑的 `TextPainter` 直排，
    /// 富文本等「帧永不等出图」做扎实了再开。
    this.useRichContent = false,

    /// 写剪贴板（M42「复制本题答案」/右键复制所选）；单测注入记录用。
    Future<void> Function(String text)? writeClipboard,
  })  : contentBuilder = contentBuilder ?? FloatContentBuilder(),
        _writeClipboard = writeClipboard ?? _defaultClipboardWrite,
        _measureRich = measureRichContent ?? measureRichContentHeight,
        _rasterRich = rasterRichContent ?? rasterRichTile {
    // 合成器的内容片交给富文本渲染（M40）：公式/化学式/表格与主界面同源。
    // 单测会自己塞一个假合成器，所以这里只在没给的时候接管。
    this.composer = composer ??
        FloatFrameComposer(
          renderContentTile: useRichContent ? _contentTile : null,
          contentChunkHeight: useRichContent
              ? kFloatRichChunkHeight
              : kFloatContentTileHeight,
        );
  }

  final FloatWindowSurface window;
  final CoreRepository repo;
  final CaptureCoordinator coordinator;
  final AppSettings Function() settings;
  final Future<void> Function(AppSettings) saveSettings;
  final bool Function() appIsDark;
  final double Function() devicePixelRatioOf;
  final ui.Size Function() screenLogicalSizeOf;

  /// 内容是否走「与主界面同源的富文本渲染」（公式/化学式/表格）。
  ///
  /// **默认关**（见构造函数注释）：富文本一次出图 300–700 ms，只要它还在推帧
  /// 链路上，滚动就会被它拖住。开着时单个内容片高 [kFloatRichChunkHeight]。
  final bool useRichContent;

  /// 分块缓存 + CPU 合成（M36）：只有内容/外观变化时才出图。
  late final FloatFrameComposer composer;

  /// 老的 `TextPainter` 直排内容构建器：富文本渲染上线后不再用于出图，
  /// 保留给单测与「离屏管线不可用」时的兜底路径。
  final FloatContentBuilder contentBuilder;

  /// 量富文本内容高度 / 栅格化一片（可注入，单测塞假实现以避开 toImage）。
  final FloatRichMeasurer _measureRich;
  final FloatRichTileRasterizer _rasterRich;

  /// 当前这一帧的富文本输入（合成器按片出图时读它）。
  FloatRichSpec? _richSpec;

  /// 量过的高度缓存（键 = spec.key），最多留 4 条。
  final Map<int, double> _richHeights = {};

  List<Session> _sessions = const [];
  List<Question> _questions = const [];
  int _index = 0;
  double _scroll = 0;
  String? _loadedSessionId;
  bool _visible = false;
  String? _hoveredId;
  bool _contentFailed = false;

  FloatFrame? _frame;
  bool _dirty = false;

  /// 慢帧告警阈值（毫秒）与上一次告警时间（5 秒最多一条）。
  static const int _slowPushMs = 40;

  /// 上一帧开始的墙钟时间（诊断「帧间隔」用）。
  int _lastPushWall = 0;

  /// 帧耗时汇总（每 100 帧写一条 info）：诊断输出**绝不能**变成瓶颈 ——
  /// 之前把阈值压到 6 ms 时几乎每帧都同步写日志文件，写盘把 isolate 卡住，
  /// 反而量出「每帧 650 ms」的假象。
  int _pushCount = 0;
  int _accPushUs = 0;
  int _accComposeUs = 0;
  int _accGapUs = 0;
  int _lastSlowLogAt = 0;

  /// 本轮 `_push` 里排了几次（>1 = 期间又有事件进来，推帧跟不上事件）。
  int _pushRounds = 0;

  /// 正在进行的这一轮绘制。**`show()` / `applySettings()` 必须能等到它完成**：
  /// 否则调用方会以为「已经画好了」继续往下走，而窗口上其实还什么都没有。
  Completer<void>? _pushCompleter;

  /// 当前看的是哪一次识别（null = 还没有记录）。
  String? get currentSessionId => _sessions.isEmpty
      ? null
      : _sessions[_index.clamp(0, _sessions.length - 1)].sessionId;

  int get sessionCount => _sessions.length;
  bool get isVisible => _visible;
  double get contentHeight => _lastContentHeight;
  double _lastContentHeight = 0;

  // ------------------------------------------------------------------
  // 数据
  // ------------------------------------------------------------------

  /// 会话列表变化（外壳订阅 `sessionsProvider` 后推进来）。
  ///
  /// **保留用户当前看的那一次**：识别过程中会话行会被反复改写（状态/题数），
  /// 每次都跳回最新那条会把正在翻旧记录的用户拽走。只有「原来那条没了」或
  /// 「识别刚结束」才回到最新（后者由 [onBusyChanged] 显式处理）。
  void setSessions(List<Session> sessions) {
    final list = sessions.where((s) => !s.isDeleted).toList();
    final current = currentSessionId;
    _sessions = list;
    var keepScroll = false;
    // M44 第 5 条：手机刚识别完，列表一到就跳到最新那一次（见 [onRemoteTask]）。
    if (_jumpToNewest) {
      _jumpToNewest = false;
      _index = 0;
    } else if (current != null) {
      final i = list.indexWhere((s) => s.sessionId == current);
      if (i >= 0) {
        _index = i;
        keepScroll = true;
      } else {
        _index = 0;
      }
    } else {
      _index = 0;
    }
    if (_index >= _sessions.length) _index = 0;
    unawaited(_reload(keepScroll: keepScroll, force: true));
  }

  /// 手机（安卓）发起的任务状态（M44 第 5 条）。
  ///
  /// 用户报「windows 端悬浮窗显示时，若在手机端搜题，悬浮窗不会同步状态与跳转
  /// 新界面」：以前悬浮窗只认本机 coordinator 的 busy 与「保留当前会话」的策略，
  /// 手机那边发生什么它一无所知。现在：
  /// - `queued` / `analyzing` → 显示「手机正在识别…」浮层；
  /// - `done` / `failed` → **跳到最新那一次**（用户拿起手机搜题，就是想在悬浮窗
  ///   直接看到结果；[setSessions] 里的 `_jumpToNewest` 负责等列表到位）。
  void onRemoteTask(RemoteTaskSignal signal) {
    final wasBusy = _remoteBusy;
    _remoteBusy = signal.busy;
    if (signal.busy) {
      if (!wasBusy) unawaited(_push());
      return;
    }
    if (signal.finished) {
      _jumpToNewest = true;
      _index = 0;
      _scroll = 0;
      AppLogger.instance.info('float-window',
          '手机任务结束（${signal.status}，会话 ${signal.sessionId ?? '-'}）：悬浮窗跳到最新一次识别');
      unawaited(_reload(keepScroll: false, force: true));
      return;
    }
    unawaited(_push());
  }

  /// 打开悬浮窗（外壳在启动完成或用户打开开关时调用）。
  Future<void> show() async {
    _visible = true;
    final app = settings();
    // 顺序要紧：先说 DPR（原生侧的位置/热区都是物理像素），再定位、再显示。
    window.setDevicePixelRatio(devicePixelRatioOf());
    window.setLocked(app.floatWindowLocked);
    window.setTopmost(app.floatWindowTopmost);
    window.setPosition(_resolveX(app), _resolveY(app));
    await window.show();
    await _reload(keepScroll: false);
  }

  void hide() {
    _visible = false;
    _hoveredId = null;
    window.hide();
  }

  /// 设置变了（外观/配色/透明度/字号/锁定/置顶/极简/**位置**）→ 应用到窗口并重画。
  Future<void> applySettings() async {
    final app = settings();
    window.setDevicePixelRatio(devicePixelRatioOf());
    window.setLocked(app.floatWindowLocked);
    window.setTopmost(app.floatWindowTopmost);
    // 位置也要重新应用：设置页的「恢复默认位置」只改 x/y（= -1），
    // 不在这里摆一次的话窗口根本不会动。
    window.setPosition(_resolveX(app), _resolveY(app));
    if (!_visible) return;
    await _push();
  }

  /// 暂存页数变化（多页模式进出）。
  void onStagingChanged() => unawaited(_push());

  /// 「正在识别」状态变化：识别中显示提示；结束后跳回最新那次。
  void onBusyChanged() {
    if (!coordinator.busy) {
      // 用户需求 1.10：结束后跳转最新识别界面。
      _index = 0;
      _scroll = 0;
      unawaited(_reload(keepScroll: false));
      return;
    }
    unawaited(_push());
  }

  /// 极简模式下的文本选区（**内容坐标**；null = 没有选区）。
  ///
  /// 用户口径（M42）：「希望极简模式可以变成可选中字符的形式，便于我的选中与复制」。
  /// 选区存在内容坐标里，所以滚动时选区跟着内容走。
  FloatTextSelection? _selection;

  /// 拖选时算出来的高亮与文本（每次推帧重算，纯函数、很便宜）。
  FloatSelectionResult _selectionResult = FloatSelectionResult.none;

  /// 一次性提示（「已复制本次识别内容」/「已复制所选」），1.4 秒后自己消失。
  String? _tip;
  Timer? _tipTimer;

  /// 手机端任务是否正在识别（M44 第 5 条）：悬浮窗的「识别中」浮层要对两头都亮。
  bool _remoteBusy = false;


  /// 会话列表下一次刷新时**强制跳到最新**（手机任务刚结束，见 [onRemoteTask]）。
  bool _jumpToNewest = false;

  /// 写剪贴板（可注入，单测里换成记录调用）。
  final Future<void> Function(String text) _writeClipboard;

  /// 鼠标悬停到某个按钮（图标按钮的提示）。
  ///
  /// **只认顶部第一栏的按钮**：底部「识别一张 / 多页识别」对悬停没有任何反应
  /// （Dock 式放大已经被用户否掉），为它们重画一整帧只是白白卡一下。
  void setHovered(String? id) {
    final next = kFloatHeaderActions.contains(id) ? id : null;
    if (_hoveredId == next) return;
    _hoveredId = next;
    unawaited(_push());
  }

  double _resolveX(AppSettings app) {
    final screen = screenLogicalSizeOf();
    final w = app.floatWindowWidthLogical;
    if (app.floatWindowX >= 0) {
      return app.floatWindowX
          .clamp(0.0, (screen.width - w).clamp(0.0, screen.width));
    }
    // 默认：屏幕右侧、不贴边（用户需求 1.6）。
    return (screen.width - w - kFloatWindowDefaultMarginX)
        .clamp(0.0, screen.width);
  }

  double _resolveY(AppSettings app) {
    final screen = screenLogicalSizeOf();
    final h = app.floatWindowHeightLogical;
    if (app.floatWindowY >= 0) {
      return app.floatWindowY
          .clamp(0.0, (screen.height - h).clamp(0.0, screen.height));
    }
    // 竖屏外观很高：默认位置夹到「屏幕高度 - 窗口高度」以内，别一开就超出屏幕。
    return kFloatWindowDefaultMarginY
        .clamp(0.0, (screen.height - h).clamp(0.0, screen.height));
  }

  /// 归位（设置页「恢复默认位置」）。
  Future<void> resetPosition() async {
    final app = settings();
    final x = (screenLogicalSizeOf().width -
            app.floatWindowWidthLogical -
            kFloatWindowDefaultMarginX)
        .clamp(0.0, screenLogicalSizeOf().width);
    await saveSettings(app.copyWith(
        floatWindowX: x, floatWindowY: kFloatWindowNoPosition));
    window.setDevicePixelRatio(devicePixelRatioOf());
    window.setPosition(x, _resolveY(settings()));
    await _push();
  }

  /// 重新读取当前会话的题目并重画。
  Future<void> _reload({required bool keepScroll, bool force = false}) async {
    if (!keepScroll) _scroll = 0;
    final sid = currentSessionId;
    if (!force && sid == _loadedSessionId && keepScroll) {
      await _push();
      return;
    }
    _loadedSessionId = sid;
    if (sid == null) {
      _questions = const [];
    } else {
      try {
        _questions = await repo.questionsOfSession(sid);
      } catch (_) {
        _questions = const [];
      }
    }
    await _push();
  }

  // ------------------------------------------------------------------
  // 渲染
  // ------------------------------------------------------------------

  FloatWindowModel buildModel({
    List<FloatNode> content = const [],
    double contentHeight = 0,
  }) {
    final app = settings();
    final dark = switch (app.floatWindowTheme) {
      FloatWindowTheme.light => false,
      FloatWindowTheme.dark => true,
      FloatWindowTheme.followApp => appIsDark(),
    };
    final total = _sessions.length;
    final session = total == 0 ? null : _sessions[_index.clamp(0, total - 1)];
    return FloatWindowModel(
      palette: FloatWindowPalette.of(
          dark: dark, paletteId: app.floatWindowPalette),
      index: _index,
      total: total,
      createdAt: session?.createdAt ?? 0,
      // M44 第 5 条：手机在搜题时，悬浮窗也要显示「手机正在识别…」。
      busy: coordinator.busy || _remoteBusy,
      busyText: coordinator.busy ? coordinator.busyLabel : '手机正在识别…',
      minimal: app.floatWindowMinimal,
      locked: app.floatWindowLocked,
      multiPage: coordinator.stagedCount > 0,
      stagedCount: coordinator.stagedCount,
      multiPageLimit: app.multiPageLimit,
      fontScale: app.floatWindowFontScale,
      scrollPx: _scroll,
      content: content,
      contentHeight: contentHeight,
      hoveredId: _hoveredId,
      contentFailed: _contentFailed,
      tipText: _tip,
      emptyText: session == null
          ? '还没有识别记录，点下面的按钮开始识别'
          : (session.status == TaskState.failed
              ? '这次识别失败了：${session.errorMessage ?? session.errorCode ?? '未知原因'}'
              : '这道题没有识别到题目，可在主窗口里重新分析或框选重试'),
    );
  }

  /// 极简模式（M33 第 7/12 条）下先把题目裁剪成「只看题目答案」。
  List<Question> _viewQuestions(AppSettings app) => app.floatWindowMinimal
      ? _questions.map(abstractQuestion).toList()
      : _questions;

  Future<void> _push() async {
    if (!_visible) return;
    final inFlight = _pushCompleter;
    if (inFlight != null) {
      _dirty = true;
      return inFlight.future;
    }
    final completer = Completer<void>();
    _pushCompleter = completer;
    _pushRounds = 0;
    try {
      do {
        _dirty = false;
        _pushRounds++;
        final nowWall = DateTime.now().millisecondsSinceEpoch;
        final gapMs = _lastPushWall == 0 ? 0 : nowWall - _lastPushWall;
        _lastPushWall = nowWall;
        final sw = Stopwatch()..start();
        final app = settings();
        final w = app.floatWindowWidthLogical;
        final h = app.floatWindowHeightLogical;
        final dpr = devicePixelRatioOf();
        final dark = switch (app.floatWindowTheme) {
          FloatWindowTheme.light => false,
          FloatWindowTheme.dark => true,
          FloatWindowTheme.followApp => appIsDark(),
        };

        // 1) 内容：主界面同一套 `QuestionCard` 富文本渲染（M40，公式/化学式/表格
        //    与主界面一致）。这里只**量高度**（按指纹缓存），出图交给合成器按片做。
        var chrome = layoutFloatWindow(buildModel(), width: w, height: h);
        final tChrome = sw.elapsedMicroseconds;
        var contentNodes = const <FloatNode>[];
        var tContent = tChrome;
        final palette = FloatWindowPalette.of(
            dark: dark, paletteId: app.floatWindowPalette);
        _lastBackgroundArgb = palette.background;
        var contentHeight = 0.0;
        _richSpec = null;
        if (chrome.bodyRect.width > 20) {
          final spec = FloatRichSpec(
            questions: _viewQuestions(app),
            width: chrome.bodyRect.width,
            fontSize: 13.0 * app.floatWindowFontScale,
            fontWeight: 400,
            minimal: app.floatWindowMinimal,
            accent: palette.accent,
            dark: dark,
            emptyText: buildModel().emptyText,
            failed: _contentFailed,
          );
          if (useRichContent) {
            try {
              contentHeight = await _measureRichCached(spec);
              await _ensureRichChunks(spec, contentHeight);
            } catch (e, st) {
              AppLogger.instance.warn('float-window', '悬浮窗内容排版失败：$e\n$st');
              _contentFailed = true;
              contentHeight = 0;
            }
            _richSpec = spec;
          } else {
            // 老路径（默认）：`TextPainter` 直排 + 按指纹缓存，实测平均整帧 6–11 ms。
            FloatContent? built;
            try {
              built = contentBuilder.build(
                key: FloatContentKey(
                  sessionId: currentSessionId ?? '',
                  signature: questionsSignature(_viewQuestions(app)),
                  width: chrome.bodyRect.width,
                  fontSize: 13.0 * app.floatWindowFontScale,
                  minimal: app.floatWindowMinimal,
                  paletteId: app.floatWindowPalette,
                  dark: dark,
                ),
                questions: _viewQuestions(app),
                palette: palette,
              );
            } catch (e, st) {
              AppLogger.instance.warn('float-window', '悬浮窗内容排版失败：$e\n$st');
              built = null;
            }
            _contentFailed = built == null;
            contentNodes = built?.nodes ?? const <FloatNode>[];
            contentHeight = built?.height ?? 0;
            _richSpec = null;
          }
          _lastContentHeight = contentHeight;
          tContent = sw.elapsedMicroseconds;
        } else {
          _contentFailed = false;
          _lastContentHeight = 0;
          contentNodes = const <FloatNode>[];
        }

        // 2) 有了内容高度再排一次外观（滚动量才能算对），必要时再排一次夹住滚动。
        chrome = layoutFloatWindow(
          buildModel(content: contentNodes, contentHeight: contentHeight),
          width: w,
          height: h,
        );
        if (_scroll > chrome.scrollMax) {
          _scroll = chrome.scrollMax;
          chrome = layoutFloatWindow(
            buildModel(content: contentNodes, contentHeight: contentHeight),
            width: w,
            height: h,
          );
        }
        _frame = chrome;
        final tLayout = sw.elapsedMicroseconds;

        // 极简模式的文本选区（M42）：纯函数重算一遍（几微秒），再换算成**窗口坐标**
        // 交给合成器直接调像素（`_paintSelection`）。
        _selectionResult = app.floatWindowMinimal && _selection != null
            ? resolveSelection(contentNodes, _selection)
            : FloatSelectionResult.none;
        final selectionRects = _selectionResult.isEmpty
            ? const <Rect>[]
            : [
                for (final r in _selectionResult.rects)
                  r.shift(Offset(
                      chrome.bodyRect.left, chrome.bodyRect.top - _scroll)),
              ];

        // 3) 分块合成：内容/外观没变时这里只做内存拷贝（微秒级），不再出图。
        // M38：热路径（滚动/悬停，三块都在缓存里）走**同步**合成 + **同步**贴帧，
        // 一次 await 都不做。
        //
        // 为什么连 `await window.setFrame(...)` 都不能有（M38 实测，同一份 exe 做 A/B）：
        // 悬浮窗的滚轮/悬停回调是从**窗口过程**（原生回调）里进到 Dart 的，此时排下的
        // 微任务要等平台线程下一次唤醒才会被跑到 —— 而平台线程只在「有 Dart 定时器到期」
        // 或「来了新的窗口消息」时才被唤醒。实测同一次滚动：
        //   贴帧 await 在（有 200ms 定时器时）1–6 ms，在（没有定时器时）**390–670 ms**，
        //   整帧因此从 7 ms 变成 671 ms、帧率掉到 ~1 fps（用户原话「滚动卡的不能用」）。
        // `setFrame` 的实现体里没有任何 await（纯 win32：写 DIB + `UpdateLayeredWindow`），
        // 所以不 await 它并不会「没画上去」—— 它本来就是同步画完的，await 只买到一次微任务。
        final fast = composer.composeFast(
          frame: chrome,
          palette: palette,
          devicePixelRatio: dpr,
          scrollPx: _scroll,
          opacity: app.floatWindowOpacity,
          cornerRadius: kFloatWindowCornerRadius,
          contentSignature: _richSpec?.contentSignature ?? 0,
          selectionRects: selectionRects,
          selectionArgb: palette.accent,
        );
        ComposeResult composed;
        if (fast != null) {
          composed = fast;
          unawaited(_blit(composed, chrome, dpr, textSelectable: app.floatWindowMinimal));
        } else {
          composed = await composer.compose(
            frame: chrome,
            palette: palette,
            devicePixelRatio: dpr,
            scrollPx: _scroll,
            opacity: app.floatWindowOpacity,
            cornerRadius: kFloatWindowCornerRadius,
            contentSignature: _richSpec?.contentSignature ?? 0,
            selectionRects: selectionRects,
            selectionArgb: palette.accent,
          );
          await _blit(composed, chrome, dpr, textSelectable: app.floatWindowMinimal);
        }
        final tCompose = sw.elapsedMicroseconds;
        sw.stop();
        _pushCount++;
        _accPushUs += sw.elapsedMicroseconds;
        _accComposeUs += (tCompose - tLayout);
        _accGapUs += gapMs * 1000;
        if (_pushCount % 100 == 0) {
          AppLogger.instance.info('float-window',
              '推帧汇总：$_pushCount 帧 · 平均整帧 ${(_accPushUs / 1000 / _pushCount).round()}ms'
              '（合成 ${(_accComposeUs / 1000 / _pushCount).round()}ms）'
              ' · 平均帧间隔 ${(_accGapUs / 1000 / _pushCount).round()}ms'
              ' · 内容高 ${contentHeight.round()} · 合成器 ${composer.debugState()}');
        }
        _logIfSlow(sw.elapsedMilliseconds, chrome, contentHeight,
            sw.elapsedMicroseconds,
            tChrome: tChrome,
            tContent: tContent,
            tLayout: tLayout,
            tCompose: tCompose,
            gapMs: gapMs);
      } while (_dirty);
    } catch (e, st) {
      AppLogger.instance.warn('float-window', '悬浮窗渲染失败：$e\n$st');
    } finally {
      _pushCompleter = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// 内容「片」的位图缓存：键 = `spec.key * 31 + 片号`。
  ///
  /// **内容一变就把所有片渲完**（[`_ensureRichChunks`]）：富文本一次出图 300–500 ms，
  /// 如果留给滚动路径按需出图，用户每滚到新片就会卡一下（1.0.6 实测「滑动卡的不行」，
  /// 1.0.7 把片放大成一张大图则变成首屏冻结 1–2 s）。渲完之前保持上一帧，于是
  /// **滚动与悬停永远是纯拷贝**，代价只是「新结果第一次显示」多等一次。
  final Map<int, Uint8List> _richChunks = {};
  int _richChunksSpecKey = 0;

  /// 这一套内容的片是不是都渲好了。
  Future<void> _ensureRichChunks(FloatRichSpec spec, double contentHeight) async {
    if (contentHeight <= 0) return;
    if (_richChunksSpecKey != spec.key) {
      _richChunks.clear();
      _richChunksSpecKey = spec.key;
    }
    final count =
        (contentHeight / kFloatRichChunkHeight).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < count; i++) {
      final key = spec.key * 31 + i;
      if (_richChunks.containsKey(key)) continue;
      final top = i * kFloatRichChunkHeight;
      final h = math.min(kFloatRichChunkHeight, contentHeight - top);
      if (h <= 0) continue;
      final dpr = devicePixelRatioOf();
      _richChunks[key] = await _rasterRich(spec,
          tileTop: top,
          tileHeight: h,
          devicePixelRatio: dpr,
          backgroundArgb: _lastBackgroundArgb,
          opacity: settings().floatWindowOpacity);
    }
  }

  /// 内容区底色（渲染片时要铺满；跟当前配色走）。
  int _lastBackgroundArgb = 0xFFFFFFFF;

  /// 量内容高度（按指纹缓存：同一套内容只量一次）。
  Future<double> _measureRichCached(FloatRichSpec spec) async {
    final hit = _richHeights[spec.key];
    if (hit != null) return hit;
    final h = await _measureRich(spec);
    _richHeights[spec.key] = h;
    while (_richHeights.length > 4) {
      _richHeights.remove(_richHeights.keys.first);
    }
    return h;
  }

  /// 合成器要一片内容时走这里（富文本离屏出图）。
  Future<Uint8List> _contentTile({
    required double width,
    required double tileTop,
    required double tileHeight,
    required double devicePixelRatio,
    required int backgroundArgb,
    double opacity = 1,
  }) {
    final spec = _richSpec;
    final pw = (width * devicePixelRatio).round().clamp(1, 8192);
    final ph = (tileHeight * devicePixelRatio).round().clamp(1, 8192);
    if (spec == null) return Future.value(Uint8List(pw * ph * 4));
    final index = (tileTop / kFloatRichChunkHeight).round();
    final key = spec.key * 31 + index;
    final hit = _richChunks[key];
    if (hit != null && hit.length == pw * ph * 4) {
      return Future.value(hit);
    }
    // 没预渲到（例如刚切了配色/宽度）：当场出一次，并留在缓存里。
    return _rasterRich(spec,
            tileTop: tileTop,
            tileHeight: tileHeight,
            devicePixelRatio: devicePixelRatio,
            backgroundArgb: backgroundArgb,
            opacity: opacity)
        .then((bytes) {
      _richChunks[key] = bytes;
      return bytes;
    });
  }

  /// 把一帧贴到原生窗口上（并把失败写进日志，别让未 await 的 Future 变成静默异常）。
  ///
  /// **热路径（[composeFast] 命中）不要 await 它的返回值**：`setFrame` 的实现体里没有
  /// 任何 await（纯 win32 同步调用），不 await 也照样已经画上去了；await 只会多排一次
  /// 微任务，而在 Windows 上从窗口过程进来的微任务要等平台线程下一次唤醒（实测
  /// 390–670 ms）。详见 `_push` 里的说明。
  Future<void> _blit(
    ComposeResult composed,
    FloatFrame frame,
    double dpr, {
    bool textSelectable = false,
  }) {
    return window
        .setFrame(
          pixels: composed.pixels,
          pixelWidth: composed.pixelWidth,
          pixelHeight: composed.pixelHeight,
          devicePixelRatio: dpr,
          hits: frame.hitRegions,
          dragRect: frame.headerRect,
          bodyRect: frame.bodyRect,
          textSelectable: textSelectable,
        )
        .catchError((Object e, StackTrace st) {
      AppLogger.instance.warn('float-window', '悬浮窗贴帧失败：$e\n$st');
    });
  }

  /// 慢帧告警：一帧超过 [_slowPushMs] 就写一条（5 秒最多一条）。
  ///
  /// 「很卡」这类反馈必须能落到具体一段上 —— 这张分解表就是第一手证据：
  /// 首屏 / 内容排版 / 再布局 / 合成 / 贴窗，外加合成器状态（哪一块重新出了图）。
  void _logIfSlow(int totalMs, FloatFrame frame, double contentHeight, int totalUs,
      {required int tChrome,
      required int tContent,
      required int tLayout,
      required int tCompose,
      int gapMs = 0}) {
    if (totalMs < _slowPushMs) return;
    final now = nowMs();
    if (now - _lastSlowLogAt < 5000) return;
    _lastSlowLogAt = now;
    int ms(int us) => (us / 1000).round();
    AppLogger.instance.warn(
        'float-window',
        '推帧偏慢 ${totalMs}ms（首屏 ${ms(tChrome)} · 内容排版 ${ms(tContent - tChrome)}'
        ' · 再布局 ${ms(tLayout - tContent)} · 合成 ${ms(tCompose - tLayout)}'
        ' · 贴窗 ${ms(totalUs - tCompose)}）· 本轮循环 $_pushRounds 次'
        ' · 内容高 ${contentHeight.round()} · 图元 ${frame.nodes.length}'
        ' · 距上帧 ${gapMs}ms · 合成器 ${composer.debugState()}');
  }

  // ------------------------------------------------------------------
  // 交互
  // ------------------------------------------------------------------

  Future<void> handleAction(String id) async {
    final app = settings();
    switch (id) {
      case FloatAction.regenerate:
        final sid = currentSessionId;
        if (sid == null) return;
        unawaited(coordinator.regenerate(sid));
      case FloatAction.toggleLock:
        await saveSettings(
            app.copyWith(floatWindowLocked: !app.floatWindowLocked));
      case FloatAction.toggleMinimal:
        // 关掉极简模式就清掉选区（富文本/卡片模式里不提供拖选，M42）。
        if (app.floatWindowMinimal) {
          _selection = null;
          _selectionResult = FloatSelectionResult.none;
        }
        await saveSettings(
            app.copyWith(floatWindowMinimal: !app.floatWindowMinimal));
      case FloatAction.copyContent:
        await copyRecognitionContent();
      case FloatAction.prev:
        if (_index < _sessions.length - 1) {
          _index++;
          await _reload(keepScroll: false);
        }
      case FloatAction.next:
        if (_index > 0) {
          _index--;
          await _reload(keepScroll: false);
        }
      case FloatAction.capture:
        unawaited(coordinator.captureAndAnalyze());
      case FloatAction.multiPage:
      case FloatAction.addPage:
        // M46：悬浮窗上的「多页识别 / 继续添加页」= 多页模式热键。到上限时**不替
        // 用户上传**（那是键盘热键的语义），而是提示他点「结束并上传」。
        unawaited(coordinator.multipageCapture(autoUploadAtLimit: false));
      case FloatAction.finishMulti:
        unawaited(coordinator.submitStaged());
      case FloatAction.cancelMulti:
        coordinator.clearStaging();
    }
    await _push();
  }

  /// 滚轮：滚动内容区（正 = 向下）。
  Future<void> scrollBy(int notches) async {
    final frame = _frame;
    if (frame == null || frame.scrollMax <= 0) return;
    final step = 60.0 * settings().floatWindowFontScale;
    _scroll = (_scroll + notches * step).clamp(0.0, frame.scrollMax);
    await _push();
  }

  /// 拖动结束：位置落库。
  Future<void> onMoveEnd(double logicalX, double logicalY) async {
    final app = settings();
    await saveSettings(
        app.copyWith(floatWindowX: logicalX, floatWindowY: logicalY));
  }

  // ------------------------------------------------------------------
  // 极简模式的文本拖选 / 复制（M42）
  // ------------------------------------------------------------------

  /// 窗口坐标 → 内容坐标（内容坐标系 y 从 0 开始、不含滚动量）。
  Offset _toContent(double x, double y) {
    final body = _frame?.bodyRect ?? Rect.zero;
    return Offset(x - body.left, y - body.top + _scroll);
  }

  /// 内容区按下：开一次拖选（此时选区是空的，等拖动才成形）。
  void onSelectBegin(double x, double y) {
    if (!settings().floatWindowMinimal) return;
    _selection = FloatTextSelection(_toContent(x, y), _toContent(x, y));
  }

  /// 拖动中：更新选区终点并重画（选区进帧指纹，所以一定重合成）。
  void onSelectUpdate(double x, double y) {
    final sel = _selection;
    if (sel == null) return;
    final focus = _toContent(x, y);
    if (focus == sel.focus) return;
    _selection = sel.to(focus);
    unawaited(_push());
  }

  /// 松手：选区成形后给一条提示（这个窗口抢不到键盘焦点，右键才是复制入口）。
  void onSelectEnd() {
    final sel = _selection;
    if (sel == null) return;
    if (_selectionResult.isEmpty) {
      _selection = null;
    } else {
      _showTip('已选中 ${_selectionResult.text.length} 个字 · 右键复制');
    }
    unawaited(_push());
  }

  /// 内容区右键：把当前选中的文本复制走。
  Future<void> copySelected() async {
    final text = _selectionResult.text;
    if (text.isEmpty) return;
    await _writeClipboard(text);
    _showTip('已复制所选 ${text.length} 个字');
    await _push();
  }

  /// 底部「复制识别内容」：把**这一次识别的全部内容**直接复制走（M43 第 2 条）。
  ///
  /// 用户口径：「修改功能为复制识别内容，点击直接复制本次识别的内容」。
  /// 复制的是**完整**内容（全部选项 + 答案 + 解析 + 阅读材料，
  /// 见 [recognitionTextOf]），不是屏幕上那份被极简排版裁剪过的视图 ——
  /// 用户要的是「能粘到别处去的结果」。
  Future<void> copyRecognitionContent() async {
    if (_questions.isEmpty) {
      _showTip('这次识别还没有内容');
      await _push();
      return;
    }
    final text = recognitionTextOf(_questions);
    if (text.isEmpty) {
      _showTip('这次识别还没有内容');
      await _push();
      return;
    }
    await _writeClipboard(text);
    _showTip('已复制本次识别内容（${_questions.length} 题）');
    await _push();
  }

  /// 显示一次性提示（1.4 秒后自己清掉）。
  void _showTip(String text) {
    _tip = text;
    _tipTimer?.cancel();
    _tipTimer = Timer(const Duration(milliseconds: 1400), () {
      _tip = null;
      unawaited(_push());
    });
  }

  void dispose() {
    _tipTimer?.cancel();
    contentBuilder.dispose();
    composer.dispose();
  }
}

/// 默认的剪贴板写入（`Clipboard` 在桌面端就是系统剪贴板）。
Future<void> _defaultClipboardWrite(String text) =>
    Clipboard.setData(ClipboardData(text: text));
