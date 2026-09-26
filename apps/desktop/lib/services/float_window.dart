import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ffi/ffi.dart';
import 'package:quizsync_core/quizsync_core.dart' show AppLogger;
import 'package:win32/win32.dart';

/// 悬浮窗需要的那一层窗口能力（原生分层窗口 / 测试替身都实现它）。
///
/// 抽出接口是为了让 `FloatWindowPresenter` 能在单测里跑：presenter 只依赖这几个
/// 动作，测试给一个记录调用的假窗口即可，不需要真的建 Win32 窗口。
abstract class FloatWindowSurface {
  Future<void> show();
  void hide();
  void setLocked(bool value);
  void setTopmost(bool value);

  /// 先告诉窗口「一逻辑像素等于几个物理像素」。
  ///
  /// **必须在 [setPosition] 之前调用**（M32 实测踩到）：原生侧的位置、热区都是
  /// 物理像素，而 `_dpr` 只在 `setFrame` 里才会被更新 —— 首次
  /// `setPosition(1016, 120)` 时 `_dpr` 还是默认的 1，于是窗口被摆到物理
  /// (1016,120) 而不是 (2032,240)，在 200% 缩放的机器上偏到屏幕左边。
  void setDevicePixelRatio(double devicePixelRatio);

  void setPosition(double logicalX, double logicalY);
  Future<void> setFrame({
    required Uint8List pixels,
    required int pixelWidth,
    required int pixelHeight,
    required double devicePixelRatio,
    required Map<String, Rect> hits,
    required Rect dragRect,

    /// 内容区矩形（逻辑像素）：拖选文本只在这个区域里开始（M42）。
    Rect bodyRect = Rect.zero,

    /// 内容区是否可拖选（极简模式才开；关着时原生根本不接管按下）。
    bool textSelectable = false,
  });
}

/// Windows 悬浮窗（M32 用户需求 1 / M33 修订）：**原生分层窗口** +
/// `UpdateLayeredWindow`。
///
/// 与悬浮球同一个套路（见 `services/floating_ball.dart` 的类注释）：不在 overlay
/// 里跑第二个 Flutter 引擎，像素由 Dart 侧离屏渲染（`float_window_view.dart` +
/// `float_window_content.dart`）之后整帧交给 DWM 合成。原生这一层只做：
///
/// 1. 建一个 `WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` 的 popup 窗口；
/// 2. 把 Dart 送来的预乘 BGRA 贴上去（[setFrame]）；
/// 3. 处理鼠标：**只有顶部第一栏能拖窗口**（M33 第 4 条，拖拽区由 Dart 给）、
///    点击（命中 Dart 送来的可点区域 → [onAction]）、悬停（[onHover]，
///    M33 第 3 条的图标提示）、滚轮（[onScroll]）；
/// 4. 截屏前隐藏（[setVisibleForCapture]）。
///
/// M33 第 15 条删掉了「拉边改比例」：外观只在三种预设里选，原生侧不再有任何
/// 改尺寸的逻辑，窗口尺寸完全由设置决定。
class FloatWindow implements FloatWindowSurface {
  FloatWindow({
    required this.onAction,
    this.onMoveEnd,
    this.onHover,
    this.onScroll,
    this.onSelectBegin,
    this.onSelectUpdate,
    this.onSelectEnd,
    this.onCopySelected,
  });

  /// 点击了某个可点区域（id 见 `FloatAction`）。
  final void Function(String id) onAction;

  /// 拖动结束（逻辑像素坐标）。
  final void Function(double x, double y)? onMoveEnd;

  /// 鼠标悬停到某个按钮上（id；移开时传 null）——用来画图标按钮的提示。
  final void Function(String? id)? onHover;

  /// 滚轮（正 = 向下滚）。
  final void Function(int notches)? onScroll;

  /// 内容区按下，开始拖选（**逻辑窗口坐标**；M42 极简模式的文本可选）。
  final void Function(double x, double y)? onSelectBegin;

  /// 拖选中（逻辑窗口坐标）。
  final void Function(double x, double y)? onSelectUpdate;

  /// 拖选结束（松手）。
  final void Function()? onSelectEnd;

  /// 在内容区右键：请求复制当前选中的文本（M42）。
  ///
  /// **为什么是右键**：这个窗口是 `WS_EX_NOACTIVATE`（不抢焦点），拿不到键盘消息，
  /// 所以 `Ctrl+C` 在它上面天生不可用；复制选区的入口只能挂在鼠标上。
  final void Function()? onCopySelected;

  int _hwnd = 0;
  NativeCallable<WNDPROC>? _proc;
  Pointer<Utf16>? _classNamePtr;
  int _hInstance = 0;

  int _memDc = 0;
  int _dib = 0;
  int _oldDib = 0;
  Pointer<Uint8> _bits = nullptr;
  int _dibW = 0;
  int _dibH = 0;

  /// 物理像素（窗口真正的大小与位置）。
  int _px = 0;
  int _py = 0;
  int _pw = 342;
  int _ph = 760;
  double _dpr = 1;

  bool _visible = false;
  bool _hiddenForCapture = false;
  bool _firstFrameLogged = false;
  bool _locked = false;
  bool _topmost = true;

  /// 当前可点区域（逻辑像素，窗口内坐标）。
  Map<String, Rect> _hits = const {};

  /// 拖拽区（逻辑像素）：**只有落在它里面的按下才开始拖窗口**（M33 第 4 条）。
  Rect _dragRect = Rect.zero;

  /// 内容区矩形（逻辑像素）+ 是否允许拖选文本（M42，极简模式才开）。
  Rect _bodyRect = Rect.zero;
  bool _textSelectable = false;

  /// 正在拖选文本。
  bool _selecting = false;

  /// 鼠标跟踪（`TrackMouseEvent` 只在需要时申请，不然每次移动都发消息太吵）。
  bool _trackingMouse = false;

  /// 当前悬停的按钮 id（避免重复上报）。
  String? _hoverId;

  // 拖动状态
  bool _dragging = false;
  int _downX = 0;
  int _downY = 0;
  int _originX = 0;
  int _originY = 0;
  bool _moved = false;

  /// 一次「按下→松开」的位移阈值（**逻辑**像素）：小于它才算点击。
  ///
  /// M47：这个值以前直接和 `GetCursorPos` 的物理像素比 —— 150% / 200% 缩放下
  /// 实际只剩 4 / 3 逻辑像素，顶部那排按钮（都在可拖拽的标题栏里）很容易被判成
  /// 拖动而点不中。真正用于比较的物理阈值见 [_clickSlopPx]。
  static const int _clickSlopLogical = 6;

  int get _clickSlopPx =>
      (_clickSlopLogical * (_dpr <= 0 ? 1.0 : _dpr)).round().clamp(1, 512);

  /// 首帧之后不再每帧 `ShowWindow`（M38）：窗口早就可见了。
  bool _shownOnce = false;

  bool get isVisible => _hwnd != 0 && _visible;
  bool get locked => _locked;
  bool get topmost => _topmost;

  /// 显示（已显示时只把当前位置再贴一次）。
  @override
  Future<void> show() async {
    try {
      if (_hwnd == 0) {
        _createWindow();
      }
      if (_hwnd == 0) return;
      ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
      _visible = true;
      AppLogger.instance
          .info('float-window', '悬浮窗窗口已显示（首帧落上后打印真实几何）');
    } catch (e, st) {
      AppLogger.instance.warn('float-window', '悬浮窗显示失败：$e\n$st');
    }
  }

  @override
  void hide() {
    if (_hwnd == 0) return;
    ShowWindow(_hwnd, SW_HIDE);
    _visible = false;
  }

  /// 截屏前后隐藏 / 恢复（悬浮窗不能出现在识别结果里）。
  void setVisibleForCapture(bool visible) {
    if (_hwnd == 0) return;
    if (!visible) {
      _hiddenForCapture = _visible;
      if (_visible) {
        ShowWindow(_hwnd, SW_HIDE);
        Sleep(120);
      }
      return;
    }
    if (_hiddenForCapture) {
      _hiddenForCapture = false;
      ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
    }
  }

  @override
  void setLocked(bool value) {
    _locked = value;
    AppLogger.instance
        .info('float-window', value ? '悬浮窗位置已锁定' : '悬浮窗位置已解锁（可拖动第一栏）');
  }

  /// 置顶开关（用户需求 1.1）。只改 Z 序，不动像素。
  @override
  void setTopmost(bool value) {
    if (_topmost == value) return;
    _topmost = value;
    if (_hwnd == 0) return;
    SetWindowPos(_hwnd, value ? _hwndTopmost : _hwndNotTopmost, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    AppLogger.instance.info('float-window', value ? '悬浮窗已置顶' : '悬浮窗取消置顶');
  }

  /// 先告诉窗口「一逻辑像素 = 几个物理像素」。**必须在 [setPosition] 之前调用**
  /// （M32 实测踩到：原生侧的坐标/尺寸都是物理像素，而 `_dpr` 只在 [setFrame] 里
  /// 更新 —— 首次定位时它还是默认 1，200% 缩放的机器上窗口会被摆到
  /// 物理 (1016,120) 而不是 (2032,240)，看起来**偏到屏幕左边**）。
  @override
  void setDevicePixelRatio(double devicePixelRatio) {
    _dpr = devicePixelRatio <= 0 ? 1 : devicePixelRatio;
  }

  /// 设置窗口位置（逻辑像素；调用方负责不要越界）。
  @override
  void setPosition(double logicalX, double logicalY) {
    _px = (logicalX * _dpr).round();
    _py = (logicalY * _dpr).round();
    if (_hwnd == 0) return;
    SetWindowPos(_hwnd, 0, _px, _py, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }

  /// 把一帧像素贴上去，并更新可点区域与拖拽区。
  ///
  /// [pixels] 必须是**预乘 alpha 的 BGRA**，长度 = pixelWidth × pixelHeight × 4。
  @override
  Future<void> setFrame({
    required Uint8List pixels,
    required int pixelWidth,
    required int pixelHeight,
    required double devicePixelRatio,
    required Map<String, Rect> hits,
    required Rect dragRect,
    Rect bodyRect = Rect.zero,
    bool textSelectable = false,
  }) async {
    if (_hwnd == 0) return;
    _dpr = devicePixelRatio <= 0 ? 1 : devicePixelRatio;
    _hits = hits;
    _dragRect = dragRect;
    _bodyRect = bodyRect;
    _textSelectable = textSelectable;
    if (pixels.length != pixelWidth * pixelHeight * 4) {
      AppLogger.instance.warn('float-window',
          '像素长度不符：期望 ${pixelWidth * pixelHeight * 4}，实际 ${pixels.length}');
      return;
    }
    final sizeChanged = pixelWidth != _pw || pixelHeight != _ph;
    _pw = pixelWidth;
    _ph = pixelHeight;
    _ensureBitmap(_pw, _ph);
    if (_bits == nullptr) return;
    _bits.asTypedList(pixels.length).setAll(0, pixels);
    if (sizeChanged) {
      _clampIntoWorkArea();
      SetWindowPos(_hwnd, 0, _px, _py, _pw, _ph,
          SWP_NOZORDER | SWP_NOACTIVATE);
    }
    _blit();
    // 第一帧之后不再每帧 `ShowWindow`：窗口早就可见了，每帧再 SHOW 一次只是白白
    // 叫一次 USER32（M38 顺手收掉；显示/隐藏的语义由 `show()` / `hide()` /
    // `setVisibleForCapture()` 负责）。
    if (_visible && !_shownOnce) {
      _shownOnce = true;
      ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
    }
    // 首帧落上去之后才打印**真实**的几何：`show()` 里打印的是「首帧之前」的
    // 占位尺寸（M32 探针实测时正好被它误导过）。
    if (!_firstFrameLogged) {
      _firstFrameLogged = true;
      AppLogger.instance.info('float-window',
          '悬浮窗首帧：物理 ($_px,$_py) $_pw×$_ph · 逻辑 '
          '${(_pw / _dpr).round()}×${(_ph / _dpr).round()} · DPR=$_dpr · '
          '置顶=$_topmost 锁定=$_locked · 可点区域 ${_hits.length} 个 · '
          '拖拽区 ${_dragRect.width.round()}×${_dragRect.height.round()}');
    }
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
  // 窗口
  // ------------------------------------------------------------------

  void _createWindow() {
    _hInstance = GetModuleHandle(nullptr);
    final className = 'QuizSyncFloatWindow'.toNativeUtf16();
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
      AppLogger.instance
          .warn('float-window', 'RegisterClassEx 返回 0（类可能已注册）');
    }
    if (_px == 0 && _py == 0) _dockDefault();
    _ensureBitmap(_pw, _ph);
    _hwnd = CreateWindowEx(
      // WS_EX_NOACTIVATE：点悬浮窗上的按钮**不抢焦点**，用户正在别的程序里
      // 打字/看题时不会被弹走（这一点对这个工具很关键）。
      WS_EX_LAYERED |
          WS_EX_TOOLWINDOW |
          WS_EX_NOACTIVATE |
          (_topmost ? WS_EX_TOPMOST : 0),
      className,
      'QuizSync 悬浮窗'.toNativeUtf16(),
      WS_POPUP,
      _px,
      _py,
      _pw,
      _ph,
      0,
      0,
      _hInstance,
      nullptr,
    );
    if (_hwnd == 0) {
      AppLogger.instance.warn('float-window', 'CreateWindowEx 失败');
    }
  }

  /// 默认位置：屏幕右侧、不贴边（用户需求 1.6）。真正的位置一般由 Dart 侧
  /// 按已保存的设置算好再 `setPosition`；这里只是兜底。
  void _dockDefault() {
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    _px = screenW - _pw - (24 * _dpr).round();
    _py = (24 * _dpr).round();
    _clampIntoWorkArea();
  }

  void _clampIntoWorkArea() {
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
    if (_px + _pw > screenW) _px = screenW - _pw;
    if (_py + _ph > screenH) _py = screenH - _ph;
    if (_px < 0) _px = 0;
    if (_py < 0) _py = 0;
  }

  void _ensureBitmap(int w, int h) {
    if (_dibW == w && _dibH == h && _bits != nullptr) return;
    _disposeBitmap();
    if (_memDc == 0) {
      final screenDc = GetDC(0);
      _memDc = CreateCompatibleDC(screenDc);
      ReleaseDC(0, screenDc);
    }
    final bmi = calloc<BITMAPINFO>();
    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = w;
    bmi.ref.bmiHeader.biHeight = -h; // 自上而下
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;
    final ppv = calloc<Pointer>();
    _dib = CreateDIBSection(_memDc, bmi, DIB_RGB_COLORS, ppv, NULL, 0);
    _bits = ppv.value.cast<Uint8>();
    calloc.free(ppv);
    calloc.free(bmi);
    _oldDib = SelectObject(_memDc, _dib);
    _dibW = w;
    _dibH = h;
  }

  void _disposeBitmap() {
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
    _dibW = 0;
    _dibH = 0;
  }

  void _blit() {
    if (_hwnd == 0 || _memDc == 0 || _dib == 0 || _bits == nullptr) {
      AppLogger.instance.warn('float-window',
          '跳过绘制（hwnd=$_hwnd dc=$_memDc dib=$_dib bits=$_bits）');
      return;
    }
    // M47：`hWndInsertAfter = 0` 是 `HWND_TOP`（把窗口提到最上面），**不是**
    // 「Z 序不动」。非置顶时每帧都这么调，等于「取消置顶」永远无效。真正的
    // 「别动 Z 序」是加 `SWP_NOZORDER` —— Z 序只在 `setTopmost` 里改一次。
    SetWindowPos(
        _hwnd,
        _topmost ? _hwndTopmost : _hwndNotTopmost,
        _px,
        _py,
        _pw,
        _ph,
        _topmost ? SWP_NOACTIVATE : SWP_NOACTIVATE | SWP_NOZORDER);
    final screenDc = GetDC(0);
    final dst = calloc<POINT>()
      ..ref.x = _px
      ..ref.y = _py;
    final size = calloc<SIZE>()
      ..ref.cx = _pw
      ..ref.cy = _ph;
    final src = calloc<POINT>()..ref.x = 0;
    final blend = calloc<BLENDFUNCTION>()
      ..ref.BlendOp = _acSrcOver
      // 透明度已经在 Dart 侧乘进像素（M38），这里恒 255。
      // 注：M36 曾把整窗透明度交给这里的 `SourceConstantAlpha`。M38 用同一份 exe
      // 做过 A/B（`QUIZSYNC_FW_DWMALPHA`），两条路的分段耗时一样 —— 真正让滚动掉到
      // 1 fps 的是热路径上那次 `await`（见 `float_window_presenter.dart`），不是这里；
      // 保留「乘进像素」是因为它不依赖 DWM 的混合路径。
      ..ref.SourceConstantAlpha = 255
      ..ref.AlphaFormat = _acSrcAlpha;
    try {
      final ok = _updateLayeredWindow(
          _hwnd, screenDc, dst, size, _memDc, src, 0, blend, ULW_ALPHA);
      if (ok == 0) {
        AppLogger.instance
            .warn('float-window', 'UpdateLayeredWindow 失败（$_px,$_py）');
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
  // 消息
  // ------------------------------------------------------------------

  int _wndProc(int hwnd, int msg, int wParam, int lParam) {
    try {
      switch (msg) {
        case WM_LBUTTONDOWN:
          _onDown(hwnd, _xParam(lParam), _yParam(lParam));
          return 0;
        case WM_MOUSEMOVE:
          _onMove(_xParam(lParam), _yParam(lParam));
          return 0;
        case WM_LBUTTONUP:
          _onUp();
          return 0;
        case WM_RBUTTONDOWN:
          // 内容区右键 = 复制所选（见 [onCopySelected] 的说明）。
          if (_inBodyRect(_xParam(lParam), _yParam(lParam))) {
            onCopySelected?.call();
            return 0;
          }
          return DefWindowProc(hwnd, msg, wParam, lParam);
        case WM_MOUSEWHEEL:
          final notches = -_hiWordSigned(wParam) ~/ 120;
          if (notches != 0) onScroll?.call(notches);
          return 0;
        case _wmMouseLeave:
          _trackingMouse = false;
          _setHover(null);
          return 0;
        case WM_MOUSEACTIVATE:
          // 不激活窗口（保持 WS_EX_NOACTIVATE 的语义）。
          return _maNoActivate;
        case WM_DESTROY:
          return 0;
      }
      return DefWindowProc(hwnd, msg, wParam, lParam);
    } catch (e) {
      AppLogger.instance.warn('float-window', '悬浮窗消息处理失败：$e');
      return 0;
    }
  }

  /// 鼠标在窗口内的位置是否落在某个可点区域上（返回 id）。
  String? _hitAt(int x, int y) {
    for (final e in _hits.entries) {
      final r = e.value;
      final phys = Rect.fromLTWH(
          r.left * _dpr, r.top * _dpr, r.width * _dpr, r.height * _dpr);
      if (phys.contains(Offset(x.toDouble(), y.toDouble()))) return e.key;
    }
    return null;
  }

  /// 该点是否在拖拽区（顶部第一栏）里。
  bool _inDragRect(int x, int y) {
    final r = _dragRect;
    if (r.width <= 0 || r.height <= 0) return false;
    final phys = Rect.fromLTWH(
        r.left * _dpr, r.top * _dpr, r.width * _dpr, r.height * _dpr);
    return phys.contains(Offset(x.toDouble(), y.toDouble()));
  }

  /// 该点是否在内容区里（M42：拖选文本的起点判定）。
  bool _inBodyRect(int x, int y) {
    final r = _bodyRect;
    if (r.width <= 0 || r.height <= 0) return false;
    final phys = Rect.fromLTWH(
        r.left * _dpr, r.top * _dpr, r.width * _dpr, r.height * _dpr);
    return phys.contains(Offset(x.toDouble(), y.toDouble()));
  }

  void _setHover(String? id) {
    if (id == _hoverId) return;
    _hoverId = id;
    onHover?.call(id);
  }

  void _onDown(int hwnd, int x, int y) {
    final pt = calloc<POINT>();
    GetCursorPos(pt);
    _downX = pt.ref.x;
    _downY = pt.ref.y;
    calloc.free(pt);
    _originX = _px;
    _originY = _py;
    _moved = false;
    SetCapture(hwnd);
    // M33 第 4 条：**只有顶部第一栏**能拖动窗口。
    _dragging = !_locked && _inDragRect(x, y);
    // M42：内容区里按下（且极简模式开着）就开始拖选文本 —— 原生只负责把
    // **逻辑坐标**原样转给 Dart，命中的是哪个字由 Dart 那边算。
    _selecting = false;
    if (!_dragging && _textSelectable && _inBodyRect(x, y)) {
      _selecting = true;
      onSelectBegin?.call(x / _dpr, y / _dpr);
    }
  }

  void _onMove(int x, int y) {
    if (!_trackingMouse) {
      _trackingMouse = true;
      final tme = calloc<_TrackMouseEventStruct>();
      tme.ref
        ..cbSize = sizeOf<_TrackMouseEventStruct>()
        ..dwFlags = _tmeLeave
        ..hwndTrack = _hwnd
        ..dwHoverTime = 0;
      _trackMouseEvent(tme);
      calloc.free(tme);
    }
    if (_selecting) {
      // 拖选：把当前逻辑坐标报给 Dart（选区与高亮都在那边算）。
      onSelectUpdate?.call(x / _dpr, y / _dpr);
      return;
    }
    if (_dragging) {
      final pt = calloc<POINT>();
      GetCursorPos(pt);
      final cx = pt.ref.x;
      final cy = pt.ref.y;
      calloc.free(pt);
      if ((cx - _downX).abs() > _clickSlopPx ||
          (cy - _downY).abs() > _clickSlopPx) {
        _moved = true;
      }
      if (_moved) {
        _px = _originX + (cx - _downX);
        _py = _originY + (cy - _downY);
        SetWindowPos(_hwnd, 0, _px, _py, 0, 0,
            SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      }
    }
    // 悬停高亮 / 图标提示：任何时刻都跟着鼠标更新。
    _setHover(_hitAt(x, y));
  }

  void _onUp() {
    ReleaseCapture();
    if (_selecting) {
      // 拖选结束：这次按下**不再当成点击**（否则松手会顺手触发下面的按钮）。
      _selecting = false;
      onSelectEnd?.call();
      return;
    }
    if (!_dragging) {
      _click(_downX, _downY);
      return;
    }
    _dragging = false;
    if (_moved) {
      AppLogger.instance.info('float-window', '悬浮窗移动到 ($_px,$_py)');
      onMoveEnd?.call(_px / _dpr, _py / _dpr);
      return;
    }
    // 没移动 = 点击：按当前可点区域派发。
    _click(_downX, _downY);
  }

  /// 用**按下时的屏幕坐标**换算成窗口内坐标再查表。
  void _click(int screenX, int screenY) {
    final id = _hitAt(screenX - _px, screenY - _py);
    if (id == null) {
      AppLogger.instance
          .info('float-window', '点击空白处（${screenX - _px},${screenY - _py}）');
      return;
    }
    AppLogger.instance.info('float-window', '点击 $id');
    onAction(id);
  }
}

// --- 分层窗口所需的最小 Win32 绑定 / 常量 ---

/// `win32` 包没有导出这两个（`WM_MOUSELEAVE` / `TrackMouseEvent` 相关），
/// 自己按 Windows SDK 定义 —— 鼠标移出窗口时要清掉悬停提示，否则提示会一直挂着。
const int _wmMouseLeave = 0x02A3;
const int _tmeLeave = 0x00000002;

/// `TRACKMOUSEEVENT`：DWORD + DWORD + HWND + DWORD（x64 下 8 字节对齐 → 24 字节）。
final class _TrackMouseEventStruct extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwFlags;

  @IntPtr()
  external int hwndTrack;

  @Uint32()
  external int dwHoverTime;
}

const int _acSrcOver = 0x00;
const int _acSrcAlpha = 0x01;
const int _hwndTopmost = -1;
const int _hwndNotTopmost = -2;
const int _maNoActivate = 3;

int _loWord(int v) => v & 0xFFFF;
int _hiWordSigned(int v) {
  final h = (v >> 16) & 0xFFFF;
  return h >= 0x8000 ? h - 0x10000 : h;
}

int _xParam(int l) {
  final x = _loWord(l);
  return x >= 0x8000 ? x - 0x10000 : x;
}

int _yParam(int l) {
  final y = (l >> 16) & 0xFFFF;
  return y >= 0x8000 ? y - 0x10000 : y;
}

final DynamicLibrary _user32Lib = DynamicLibrary.open('user32.dll');

typedef _UpdateLayeredWindowNative = Int32 Function(
    IntPtr, IntPtr, Pointer<POINT>, Pointer<SIZE>, IntPtr, Pointer<POINT>,
    Uint32, Pointer<BLENDFUNCTION>, Uint32);
typedef _UpdateLayeredWindowDart = int Function(
    int, int, Pointer<POINT>, Pointer<SIZE>, int, Pointer<POINT>, int,
    Pointer<BLENDFUNCTION>, int);

final _UpdateLayeredWindowDart _updateLayeredWindow = _user32Lib.lookupFunction<
    _UpdateLayeredWindowNative, _UpdateLayeredWindowDart>('UpdateLayeredWindow');

typedef _TrackMouseEventNative = Int32 Function(Pointer<_TrackMouseEventStruct>);
typedef _TrackMouseEventDart = int Function(Pointer<_TrackMouseEventStruct>);

final _TrackMouseEventDart _trackMouseEvent = _user32Lib
    .lookupFunction<_TrackMouseEventNative, _TrackMouseEventDart>(
        'TrackMouseEvent');
