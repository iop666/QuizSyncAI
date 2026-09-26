import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:quizsync_core/quizsync_core.dart'
    show AppLogger, kBallStrokeInset;
import 'package:win32/win32.dart';

import 'ball_paint.dart';

/// 悬浮球三态（用户反馈 11）：每态一张图，主色**加深后**就是描边颜色。
///
/// 资源由 `tool/make_icons.dart` 从 `icon/FloatingBall_*.png` 生成：
/// **去掉球外的白底 + 圆形透明边**，因此可以缩放到任意大小而不带白方块。
enum BallState {
  idle('待识别', 'assets/floating_ball_default.png', 0xFF1D86FC),
  detecting('识别中', 'assets/floating_ball_detecting.png', 0xFFFBD705),
  multiPage('多页模式', 'assets/floating_ball_multipage.png', 0xFF1EB945);

  const BallState(this.label, this.asset, this.mainColor);

  /// 给设置页显示的名字。
  final String label;
  final String asset;

  /// 该状态的主色（ARGB）——描边颜色跟着它**加深**（[darkenBallColor]）。
  final int mainColor;
}

/// 悬浮球鼠标手势（用户反馈 M16 第 2 条）。
enum BallGesture {
  /// 左键单击（未攒页 = 单图识别；攒页中 = 结束多页并识别）。
  tap,

  /// 按住 ≥500ms（或右键）：追加一页、进入多页模式。**单击仍在多页里收尾**。
  longPress,

  /// 拖着球走（松手后吸附左/右边缘）。
  drag,
}

/// 左键手势判定：**松手时**按「按住时长 + 有没有真的拖动」判定。
///
/// 为什么不在按下 500ms 时用 `SetTimer` + `WM_TIMER` 直接触发：`WM_TIMER` 是
/// 消息队列里**优先级最低**的消息（只在队列里没有别的消息时才生成）。用户按住
/// 不放时，松手产生的 `WM_LBUTTONUP` 会先被处理，`_endDrag` 顺手 `KillTimer`，
/// 于是一次长按被判成单击 —— 表现就是「长按不灵、跟右键不一样」（用户反馈
/// M16 第 2 条：左键长按要**等于**右键，进入多页；结束多页仍是左键单击）。
///
/// 改成松手判定后不依赖任何计时器消息：长按与右键走**同一条分支**，语义完全
/// 一致；拖动优先于长按（拖着球走不该再加一页）。纯逻辑，可在单测里断言。
class BallGestureTracker {
  /// 按住多久算长按。
  static const int longPressMs = 500;

  /// 位移超过多少**逻辑**像素算拖动。
  ///
  /// M47：这个值以前直接拿去和 `GetCursorPos` 的**物理**像素比 —— 150% / 200%
  /// 缩放下实际只剩 5.3 / 4 逻辑像素，手一抖就被判成拖动，单击识别很难点中。
  /// 现在由调用方按当前 DPR 折算成物理阈值写进 [clickSlop]。
  static const double clickSlopLogical = 8;

  /// 本次手势的物理像素阈值（调用方按 DPR 设置；默认等于逻辑值，单测直接用它）。
  double clickSlop = clickSlopLogical;

  bool _pressed = false;
  bool _moved = false;
  int _downX = 0;
  int _downY = 0;
  int _downAt = 0;

  bool get pressed => _pressed;
  bool get moved => _moved;

  void press({required int x, required int y, required int nowMs}) {
    _pressed = true;
    _moved = false;
    _downX = x;
    _downY = y;
    _downAt = nowMs;
  }

  void moveTo(int x, int y) {
    if (!_pressed) return;
    if ((x - _downX).abs() > clickSlop || (y - _downY).abs() > clickSlop) {
      _moved = true;
    }
  }

  /// 松手判定。没有按下过时返回 [BallGesture.tap]（兜底：不吞掉事件）。
  BallGesture release(int nowMs) {
    if (!_pressed) return BallGesture.tap;
    _pressed = false;
    if (_moved) return BallGesture.drag;
    return nowMs - _downAt >= longPressMs
        ? BallGesture.longPress
        : BallGesture.tap;
  }

  void reset() {
    _pressed = false;
    _moved = false;
  }
}

/// Windows 悬浮球（用户反馈 11）：**原生分层窗口** + `UpdateLayeredWindow`。
///
/// 为什么不用第二个 Flutter 引擎：AGENTS.md 对安卓端的要求是「悬浮球用原生
/// View，不要在 overlay 里跑第二个 Flutter 引擎」（生命周期与内存代价）。
/// Windows 侧同理——一个 `WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_NOACTIVATE`
/// 的 popup 窗口，把预乘 BGRA 位图交给 DWM 合成，不需要引擎参与渲染。
///
/// 交互与安卓端一致（`FloatingBallManager.kt`）：
/// - 拖动移动；松手吸附最近的左/右边缘（垂直位置保留）；
/// - 8px 阈值区分点击与拖动；
/// - **左键单击** → [onTap]；**左键长按 500ms 或右键**（两条完全等价）→
///   [onLongPress] 追加一页进入多页模式（用户反馈 M16 第 2 条）；
/// - 截屏前隐藏、截完恢复，否则球会被拍进截图里。
///
/// 描边是**向外**的（用户反馈 M16 第 1 条）：画布比球体本身大出描边宽度，
/// 环带整圈落在球体之外，见 [composeBallFrame]。
class FloatingBall {
  FloatingBall({
    required this.onTap,
    required this.onLongPress,
    double sizePx = 56,
    double opacity = 0.85,
    bool strokeEnabled = false,
    double strokeWidth = 3,
    double strokeOpacity = 1,
  }) {
    _sizePx = sizePx;
    _opacity = opacity;
    _strokeEnabled = strokeEnabled;
    _strokeWidth = strokeWidth;
    _strokeOpacity = strokeOpacity;
  }

  /// 单击（与安卓一致：单图识别 / 结束多页由 Dart 决定）。
  final void Function() onTap;

  /// 左键长按 500ms / 右键（追加一页，进入多页模式）。
  final void Function() onLongPress;

  int _hwnd = 0;
  NativeCallable<WNDPROC>? _proc;
  Pointer<Utf16>? _classNamePtr;
  int _hInstance = 0;

  /// 分层窗口的位图（按需重建）。
  int _memDc = 0;
  int _dib = 0;
  int _oldDib = 0;
  Pointer<Uint8> _bits = nullptr;
  int _bitmapSize = 0;
  bool _pixelsDirty = true;

  /// 渲染缓存：预乘 BGRA 像素按「状态 + 尺寸 + 外观」缓存（用户反馈 M14 第 4 条）。
  ///
  /// 悬浮球的图是**固定素材**，切状态时完全没必要重新 `decodePng` + `copyResize`
  /// + 逐像素预乘。实测（本机探针，300 次状态/外观切换）：不做缓存时进程 RSS 从
  /// 163 MB 涨到 216 MB，用户观感就是「打开悬浮球内存飙升」；缓存后切状态只是一次
  /// `memcpy`。条目数上限很小（只有三态 × 当前尺寸/描边组合），尺寸一变即整体作废。
  final Map<String, Uint8List> _pixelCache = {};
  static const int _pixelCacheLimit = 8;

  /// 屏幕坐标（左上角）。
  int _x = 0;
  int _y = 0;

  BallState _state = BallState.idle;
  late double _sizePx;
  late double _opacity;
  late bool _strokeEnabled;
  late double _strokeWidth;
  late double _strokeOpacity;

  bool _visible = false;
  bool _hiddenForCapture = false;

  bool _dragging = false;
  int _downX = 0;
  int _downY = 0;
  int _dragOriginX = 0;
  int _dragOriginY = 0;

  /// 左键手势判定（松手时结算，用户反馈 M16 第 2 条）。
  final BallGestureTracker _gesture = BallGestureTracker();

  static int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  bool get isVisible => _hwnd != 0 && _visible;
  BallState get state => _state;

  /// 显示（已显示时只刷新内容）。
  Future<void> show() async {
    try {
      if (_hwnd == 0) _createWindow();
      if (_hwnd == 0) return;
      _pixelsDirty = true;
      await _render();
      _blit();
      ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
      _visible = true;
      AppLogger.instance.info('ball',
          '悬浮球显示于 ($_x,$_y) 窗口 ${_bitmapSize}px · 球 ${_ballPx}px · '
          '描边 ${_strokePx > 0 ? '${_strokeWidth.toStringAsFixed(1)}→${_strokePx}px' : '关'} · '
          '状态=${_state.label}');
    } catch (e, st) {
      AppLogger.instance.warn('ball', '悬浮球显示失败：$e\n$st');
    }
  }

  void hide() {
    if (_hwnd == 0) return;
    ShowWindow(_hwnd, SW_HIDE);
    _visible = false;
  }

  /// 截屏前后隐藏 / 恢复（截图里不能有球）。
  void setVisibleForCapture(bool visible) {
    if (_hwnd == 0) return;
    if (!visible) {
      _hiddenForCapture = _visible;
      if (_visible) {
        ShowWindow(_hwnd, SW_HIDE);
        Sleep(120); // 等合成器真的把窗口从画面上移除
      }
      return;
    }
    if (_hiddenForCapture) {
      _hiddenForCapture = false;
      ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
    }
  }

  /// 切换状态图（待识别 / 识别中 / 多页）。
  Future<void> setState(BallState state) async {
    if (_state == state) return;
    _state = state;
    _pixelsDirty = true;
    if (_hwnd == 0) return;
    await _render();
    _blit();
  }

  /// 外观（设置页）：大小、整体透明度、描边开关 / 粗细 / 透明度。
  Future<void> applyAppearance({
    double? sizePx,
    double? opacity,
    bool? strokeEnabled,
    double? strokeWidth,
    double? strokeOpacity,
  }) async {
    _sizePx = (sizePx ?? _sizePx).clamp(24, 160);
    _opacity = (opacity ?? _opacity).clamp(0.2, 1.0);
    _strokeEnabled = strokeEnabled ?? _strokeEnabled;
    _strokeWidth = (strokeWidth ?? _strokeWidth).clamp(0, 12);
    _strokeOpacity = (strokeOpacity ?? _strokeOpacity).clamp(0.0, 1.0);
    // 外观字段变了就要重画 —— 即使圆整后的**尺寸**没变。
    //
    // 原来只在「尺寸变了」时才把 `_pixelsDirty` 置起来，于是只改
    // **描边透明度**（尺寸不变）时 `_render()` 直接早退、窗口一像素都不变，
    // 用户观感就是「那一项调不动」。像素缓存按「状态+尺寸+描边参数」做键，
    // 重画并不会多花力气。
    _pixelsDirty = true;
    if (_hwnd == 0) return;
    final px = _targetPx;
    if (px != _bitmapSize) {
      _disposeBitmap();
      _dock(keepY: true);
    }
    await _render();
    _blit();
    if (_visible) ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
  }

  void dispose() {
    _disposeBitmap();
    if (_hwnd != 0) {
      DestroyWindow(_hwnd);
      _hwnd = 0;
    }
    if (_classNamePtr != null) {
      UnregisterClass(_classNamePtr!, _hInstance);
      calloc.free(_classNamePtr!);
      _classNamePtr = null;
    }
    _proc?.close();
    _proc = null;
  }

  // ------------------------------------------------------------------
  // 渲染
  // ------------------------------------------------------------------

  double get _devicePixelRatio {
    try {
      return PlatformDispatcher.instance.views.first.devicePixelRatio;
    } catch (_) {
      return 1;
    }
  }

  /// 球体本身的像素边长（逻辑尺寸 × DPI）。
  int get _ballPx => (_sizePx * _devicePixelRatio).round().clamp(16, 512);

  /// 向外描边的像素宽度（= 画布每侧多出来的余量）。
  int get _strokePx => (!_strokeEnabled || _strokeWidth <= 0)
      ? 0
      : (_strokeWidth * _devicePixelRatio).round();

  /// 描边再往球**内**重叠的像素（M17 第 1 条：球不是标准圆，靠它填缝）。
  int get _strokeInsetPx =>
      _strokePx == 0 ? 0 : (kBallStrokeInset * _devicePixelRatio).round();

  /// 画布 / 窗口的像素边长 = 球 + 两侧描边余量（用户反馈 M16 第 1 条）。
  int get _targetPx => _ballPx + _strokePx * 2;

  /// 生成预乘 BGRA 像素并写进 DIB。
  Future<void> _render() async {
    final size = _targetPx;
    final ballPx = _ballPx;
    final strokePx = _strokePx;
    if (size != _bitmapSize) {
      _disposeBitmap();
      _ensureBitmap(size);
      _pixelsDirty = true;
    }
    if (!_pixelsDirty || _bits == nullptr) return;

    final cached = _pixelCache[_cacheKey(size)];
    if (cached != null) {
      _bits.asTypedList(cached.length).setAll(0, cached);
      _pixelsDirty = false;
      return;
    }

    // M47：`rootBundle.load` 之后 `_state` / 外观字段可能已经变了，而 `_cacheKey`
    // 每次都读「此刻」的字段 —— 旧状态的图会被存进**新键**，于是错误的三态图
    // 一直用到尺寸/描边再变一次为止（异步竞态）。这里把本次渲染要用的状态、
    // 颜色与缓存键**先固定成快照**，加载与回写都用同一份。
    final state = _state;
    final alphaScale = _opacity;
    final strokeOpacity = _strokeOpacity;
    final insetPx = _strokeInsetPx;
    final key = _cacheKey(size);

    final data = await rootBundle.load(state.asset);
    final decoded = img.decodePng(data.buffer
        .asUint8List(data.offsetInBytes, data.lengthInBytes));
    if (decoded == null) throw StateError('悬浮球资源解码失败：${state.asset}');
    // 球按**不含描边**的边长缩放，描边是长在球外面的（用户反馈 M16 第 1 条）。
    final art = img.copyResize(decoded,
        width: ballPx, height: ballPx, interpolation: img.Interpolation.cubic);
    final frame = composeBallFrame(
      art: art,
      strokePx: strokePx,
      strokeColor: darkenBallColor(state.mainColor),
      strokeOpacity: strokeOpacity,
      insetPx: insetPx,
    );
    final out = _bits.asTypedList(size * size * 4);
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = frame.getPixel(x, y);
        final a = (p.a.toDouble() * alphaScale).round().clamp(0, 255);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        // UpdateLayeredWindow 要**预乘** alpha 的 BGRA。
        out[i++] = (b * a / 255).round();
        out[i++] = (g * a / 255).round();
        out[i++] = (r * a / 255).round();
        out[i++] = a;
      }
    }
    _remember(key: key, pixels: out);
    _pixelsDirty = false;
    // 加载期间状态/外观又变了：本帧已经过期，按最新状态再出一帧，否则屏幕上会
    // 停在旧状态图上（两次 `_render` 交错的顺序不定，谁后写谁留在屏幕上）。
    if (_cacheKey(size) != key) {
      _pixelsDirty = true;
      await _render();
    }
  }

  /// 缓存键：状态图 + 尺寸 + 描边 + 整体透明度，任一变化都要重画。
  String _cacheKey(int size) => '${_state.name}|$size|$_strokeEnabled|'
      '${_strokeWidth.toStringAsFixed(2)}|'
      '${_strokeOpacity.toStringAsFixed(2)}|${_opacity.toStringAsFixed(2)}|'
      '$_strokeInsetPx';

  void _remember({required String key, required Uint8List pixels}) {
    if (_pixelCache.length >= _pixelCacheLimit) {
      _pixelCache.remove(_pixelCache.keys.first);
    }
    // 必须复制：`pixels` 是 DIB 内存的视图，下一帧就被覆盖。
    _pixelCache[key] = Uint8List.fromList(pixels);
  }

  /// 描边与配色都在 [composeBallFrame] / [darkenBallColor] 里（纯函数、有单测）。
  void _ensureBitmap(int size) {
    if (_memDc == 0) {
      final screenDc = GetDC(0);
      _memDc = CreateCompatibleDC(screenDc);
      ReleaseDC(0, screenDc);
    }
    final bmi = calloc<BITMAPINFO>();
    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = size;
    bmi.ref.bmiHeader.biHeight = -size; // 自上而下
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;
    final ppv = calloc<Pointer>();
    _dib = CreateDIBSection(_memDc, bmi, DIB_RGB_COLORS, ppv, NULL, 0);
    _bits = ppv.value.cast<Uint8>();
    calloc.free(ppv);
    calloc.free(bmi);
    _oldDib = SelectObject(_memDc, _dib);
    _bitmapSize = size;
  }

  void _disposeBitmap() {
    // 尺寸变了，缓存的像素全部作废（键里带尺寸，留着只会白占内存）。
    _pixelCache.clear();
    if (_memDc != 0 && _oldDib != 0) {
      SelectObject(_memDc, _oldDib);
      _oldDib = 0;
    }
    if (_dib != 0) {
      DeleteObject(_dib);
      _dib = 0;
    }
    if (_memDc != 0) {
      DeleteDC(_memDc);
      _memDc = 0;
    }
    _bits = nullptr;
    _bitmapSize = 0;
  }

  /// 把 DIB 贴到分层窗口上（位置 + 内容一次交付）。
  ///
  /// `pptDst` 同时决定窗口位置，所以拖动只需要改 `_x/_y` 再重贴一次。
  /// 额外补一次 `SetWindowPos`：实测只依赖 `UpdateLayeredWindow` 的 pptDst
  /// 时窗口位置不一定跟着走，拖动会「有日志没位移」。
  void _blit() {
    if (_hwnd == 0 || _memDc == 0 || _dib == 0) {
      AppLogger.instance
          .warn('ball', '跳过绘制（hwnd=$_hwnd dc=$_memDc dib=$_dib）');
      return;
    }
    SetWindowPos(_hwnd, HWND_TOPMOST, _x, _y, _bitmapSize, _bitmapSize,
        SWP_NOACTIVATE);
    final screenDc = GetDC(0);
    final dst = calloc<POINT>()
      ..ref.x = _x
      ..ref.y = _y;
    final size = calloc<SIZE>()
      ..ref.cx = _bitmapSize
      ..ref.cy = _bitmapSize;
    final src = calloc<POINT>()..ref.x = 0;
    final blend = calloc<BLENDFUNCTION>()
      ..ref.BlendOp = _acSrcOver
      ..ref.SourceConstantAlpha = 255
      ..ref.AlphaFormat = _acSrcAlpha;
    try {
      final ok = _updateLayeredWindow(
          _hwnd, screenDc, dst, size, _memDc, src, 0, blend, ULW_ALPHA);
      if (ok == 0) {
        AppLogger.instance.warn('ball', 'UpdateLayeredWindow 失败（$_x,$_y）');
      }
    } finally {
      calloc.free(dst);
      calloc.free(size);
      calloc.free(src);
      calloc.free(blend);
      ReleaseDC(0, screenDc);
    }
  }

  // ------------------------------------------------------------------
  // 窗口
  // ------------------------------------------------------------------

  void _createWindow() {
    _hInstance = GetModuleHandle(nullptr);
    final className = 'QuizSyncFloatingBall'.toNativeUtf16();
    _classNamePtr = className;
    _proc = NativeCallable<WNDPROC>.isolateLocal(_wndProc, exceptionalReturn: 0);
    final wc = calloc<WNDCLASSEX>();
    wc.ref
      ..cbSize = sizeOf<WNDCLASSEX>()
      ..style = CS_HREDRAW | CS_VREDRAW
      ..lpfnWndProc = _proc!.nativeFunction
      ..hInstance = _hInstance
      ..lpszClassName = className;
    final atom = RegisterClassEx(wc);
    calloc.free(wc);
    if (atom == 0) {
      // 类已存在（同一进程里重建）也能继续：CreateWindowEx 仍然可用。
      AppLogger.instance.warn('ball', 'RegisterClassEx 返回 0（类可能已注册）');
    }
    // 注意：这里**不能**预先设置 `_bitmapSize`。`_render()` 用
    // `size != _bitmapSize` 判断要不要建 DIB，先写上的话 `_ensureBitmap`
    // 会被跳过，`_bits` 一直是 nullptr，`_render` 直接 return、
    // `_blit` 也因为 `_dib == 0` 静默返回 —— 窗口建出来了但**什么都没画**，
    // 屏幕上什么都看不到（实测踩过一次）。
    final px = _targetPx;
    _dock(keepY: false, size: px);
    _hwnd = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      className,
      'QuizSync 悬浮球'.toNativeUtf16(),
      WS_POPUP,
      _x,
      _y,
      px,
      px,
      0,
      0,
      _hInstance,
      nullptr,
    );
    if (_hwnd == 0) {
      AppLogger.instance.warn('ball', 'CreateWindowEx 失败');
    }
  }

  /// 默认贴右边缘、垂直 40%（与安卓一致）；[keepY] 时保留当前纵向位置。
  void _dock({required bool keepY, int? size}) {
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
    final px = size ?? (_bitmapSize == 0 ? _targetPx : _bitmapSize);
    _x = screenW - px;
    if (!keepY) {
      _y = (screenH * 0.4).round() - px ~/ 2;
    }
    _y = _y.clamp(0, (screenH - px).clamp(0, screenH));
  }

  /// 松手吸附最近的左/右边缘（垂直位置保留）。
  void _snapToEdge() {
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
    final size = _bitmapSize;
    final center = _x + size / 2;
    _x = center >= screenW / 2 ? screenW - size : 0;
    _y = _y.clamp(0, (screenH - size).clamp(0, screenH));
  }

  int _wndProc(int hwnd, int msg, int wParam, int lParam) {
    try {
      switch (msg) {
        case WM_LBUTTONDOWN:
          _beginDrag(hwnd);
          return 0;
        case WM_MOUSEMOVE:
          if (_dragging) _dragMove(hwnd);
          return 0;
        case WM_LBUTTONUP:
          _endDrag(hwnd);
          return 0;
        // 右键与「左键长按」是**同一条分支**（用户反馈 M16 第 2 条）：
        // 两个手势都只是「追加一页 / 进入多页」，具体是单图识别还是收尾识别
        // 由 Dart 侧按当前是否攒了页决定（见 `main.dart` 的 `_onBallTap`）。
        case WM_RBUTTONUP:
          AppLogger.instance.info('ball', '悬浮球：右键 → 追加一页（多页模式）');
          onLongPress();
          return 0;
        case WM_DESTROY:
          return 0;
      }
      return DefWindowProc(hwnd, msg, wParam, lParam);
    } catch (e) {
      AppLogger.instance.warn('ball', '悬浮球窗口消息处理失败：$e');
      return 0;
    }
  }

  void _beginDrag(int hwnd) {
    final pt = calloc<POINT>();
    GetCursorPos(pt);
    _downX = pt.ref.x;
    _downY = pt.ref.y;
    calloc.free(pt);
    final rect = calloc<RECT>();
    GetWindowRect(hwnd, rect);
    _dragOriginX = rect.ref.left;
    _dragOriginY = rect.ref.top;
    calloc.free(rect);
    _dragging = true;
    // 只记下按下时刻；**不**起计时器（见 BallGestureTracker 的注释）。
    // M47：阈值按当前 DPR 折算 —— 手势坐标是物理像素，而「多少算拖动」是逻辑像素。
    _gesture.clickSlop =
        BallGestureTracker.clickSlopLogical * _devicePixelRatio;
    _gesture.press(x: _downX, y: _downY, nowMs: _nowMs);
    SetCapture(hwnd);
  }

  void _dragMove(int hwnd) {
    final pt = calloc<POINT>();
    GetCursorPos(pt);
    final x = pt.ref.x;
    final y = pt.ref.y;
    calloc.free(pt);
    _gesture.moveTo(x, y);
    if (!_gesture.moved) return;
    _x = _dragOriginX + (x - _downX);
    _y = _dragOriginY + (y - _downY);
    _blit();
  }

  void _endDrag(int hwnd) {
    if (!_dragging) return;
    _dragging = false;
    ReleaseCapture();
    switch (_gesture.release(_nowMs)) {
      case BallGesture.drag:
        _snapToEdge();
        _blit();
        AppLogger.instance.info('ball', '悬浮球移动到 ($_x,$_y)');
      case BallGesture.longPress:
        AppLogger.instance.info('ball', '悬浮球：左键长按 → 追加一页（多页模式）');
        onLongPress();
      case BallGesture.tap:
        AppLogger.instance.info('ball', '悬浮球：单击');
        onTap();
    }
  }
}

// --- 分层窗口所需的最小 Win32 绑定（win32 包没有导出这两个） ---

const int _acSrcOver = 0x00;
const int _acSrcAlpha = 0x01;

final DynamicLibrary _user32Lib = DynamicLibrary.open('user32.dll');

typedef _UpdateLayeredWindowNative = Int32 Function(
    IntPtr, IntPtr, Pointer<POINT>, Pointer<SIZE>, IntPtr, Pointer<POINT>,
    Uint32, Pointer<BLENDFUNCTION>, Uint32);
typedef _UpdateLayeredWindowDart = int Function(
    int, int, Pointer<POINT>, Pointer<SIZE>, int, Pointer<POINT>, int,
    Pointer<BLENDFUNCTION>, int);

final _UpdateLayeredWindowDart _updateLayeredWindow = _user32Lib.lookupFunction<
    _UpdateLayeredWindowNative, _UpdateLayeredWindowDart>('UpdateLayeredWindow');
