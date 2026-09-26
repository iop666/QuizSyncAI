import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../state/app_info.dart' show kAppName;
import 'window_theme.dart' show findAppWindow;

/// 一次屏幕采集的原始结果（物理像素，自上而下 BGRA）。
class CapturedScreen {
  final int width;
  final int height;
  final Uint8List bgra;

  const CapturedScreen({
    required this.width,
    required this.height,
    required this.bgra,
  });
}

/// GDI BitBlt 截屏（SPEC 2.1 / AGENTS.md 技术栈）。
/// - 截取**鼠标所在显示器**的全屏；
/// - Per-Monitor DPI V2：采集线程临时切换 DPI 感知上下文，保证物理像素坐标；
/// - 截屏前隐藏主窗口由调用方负责（[hideWindowWhile]）。
class ScreenCaptureService {
  /// 截屏前需要一起隐藏的叠层（Windows 悬浮球）。参数 = 是否可见。
  ///
  /// 悬浮球是独立的分层窗口，`hideWindowWhile` 只藏主窗口是藏不掉它的 ——
  /// 不注册进来，球就会被拍进发给 AI 的那张图里。
  final List<void Function(bool visible)> overlayHiders = [];

  /// 截取鼠标所在显示器；失败抛异常。
  CapturedScreen captureCursorMonitor() {
    return using((arena) {
      // Per-Monitor DPI V2：坐标一律物理像素。
      final oldDpi =
          SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
      try {
        return _capture(arena);
      } finally {
        if (oldDpi != 0) {
          SetThreadDpiAwarenessContext(oldDpi);
        }
      }
    });
  }

  CapturedScreen _capture(Arena arena) {
    final pt = arena<POINT>();
    GetCursorPos(pt);

    final monitor = MonitorFromPoint(pt.ref, MONITOR_DEFAULTTONEAREST);
    final mi = arena<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
    if (GetMonitorInfo(monitor, mi) == 0) {
      throw StateError('GetMonitorInfo failed');
    }
    final x = mi.ref.rcMonitor.left;
    final y = mi.ref.rcMonitor.top;
    final w = mi.ref.rcMonitor.right - x;
    final h = mi.ref.rcMonitor.bottom - y;
    if (w <= 0 || h <= 0) {
      throw StateError('invalid monitor rect');
    }

    final hdcScreen = GetDC(0);
    final hdcMem = CreateCompatibleDC(hdcScreen);
    final hBitmap = CreateCompatibleBitmap(hdcScreen, w, h);
    final oldBitmap = SelectObject(hdcMem, hBitmap);
    try {
      if (BitBlt(hdcMem, 0, 0, w, h, hdcScreen, x, y, SRCCOPY) == 0) {
        throw StateError('BitBlt failed');
      }
      final bmi = arena<BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = w;
      bmi.ref.bmiHeader.biHeight = -h; // 自上而下
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_RGB;

      final pPixels = arena<Uint8>(w * h * 4);
      final got = GetDIBits(
        hdcMem,
        hBitmap,
        0,
        h,
        pPixels.cast(),
        bmi.cast(),
        DIB_RGB_COLORS,
      );
      if (got == 0) {
        throw StateError('GetDIBits failed');
      }
      final pixels = Uint8List(w * h * 4)..setRange(0, w * h * 4, pPixels.asTypedList(w * h * 4));
      return CapturedScreen(width: w, height: h, bgra: pixels);
    } finally {
      SelectObject(hdcMem, oldBitmap);
      DeleteObject(hBitmap);
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
    }
  }

  /// 截屏前隐藏主窗口，截完恢复（SPEC 2.1：不能把 UI 拍进图里）。
  ///
  /// 用窗口标题定位**本应用自己的**窗口：
  /// - `GetActiveWindow()` 返回的是「调用线程的活动窗口」，窗口只是失去焦点
  ///   （常驻后台时的常态）就可能返回 0，于是窗口不会被隐藏，上一次的答案被
  ///   一起截进图里发给 AI；
  /// - 也不能用 `GetForegroundWindow()`：热键在其他应用上按下时那是别的应用，
  ///   会把用户的浏览器/文档窗口藏起来。
  ///
  /// ⚠️ 标题必须取 `kAppName`：M17 把窗口标题从 `QuizSync AI` 改成中文名
  /// 「AI 双端搜题」时，这里留着一个 `'QuizSync AI'` 字面量，`FindWindow` 于是
  /// 返回 0、**主窗口根本没被藏**（M31 实测：`FindWindowW(NULL,"QuizSync AI")`
  /// 返回 0，`FindWindowW(NULL,"AI 双端搜题")` 返回本应用主窗口句柄）——
  /// 只要窗口可见，它自己就被拍进了发给 AI 的那张图。
  /// 现在统一走 `findAppWindow(kAppName)`，只留一个标题来源。
  T hideWindowWhile<T>(T Function() action, {Duration settle = const Duration(milliseconds: 180)}) {
    final hwnd = findAppWindow(kAppName);
    // 悬浮球之类的叠层窗口先藏（它们不受主窗口影响）。
    for (final hider in overlayHiders) {
      try {
        hider(false);
      } catch (_) {}
    }
    if (hwnd == 0) {
      try {
        return action();
      } finally {
        for (final hider in overlayHiders) {
          try {
            hider(true);
          } catch (_) {}
        }
      }
    }
    final wasVisible = IsWindowVisible(hwnd) != 0;
    // 藏之前先记下两件事（用户反馈 M15 第 3 条）：
    // ① 我们是不是当前的前台窗口 —— 只有是，恢复时才把焦点还回来；
    // ② 紧挨在我们**上面**的那个窗口 —— 恢复时插回它下面，层叠关系不变。
    //    只靠 `SW_SHOWNOACTIVATE` 虽然不抢焦点，但仍会把窗口提到同级最上层，
    //    用悬浮球时人在别的应用里，观感依旧是「界面跳出来了」。
    final wasForeground = GetForegroundWindow() == hwnd;
    final prevAbove = wasVisible ? GetWindow(hwnd, GW_HWNDPREV) : 0;
    if (wasVisible) {
      ShowWindow(hwnd, SW_HIDE);
      // 等待 compositor 真正移除窗口内容。
      Sleep(settle.inMilliseconds);
    }
    try {
      return action();
    } finally {
      if (wasVisible) {
        // 恢复可见但**不激活、不改层叠**：插回原来那个窗口下面（原来就在最上层
        // 时插到最上层）。`SetForegroundWindow` 只在「藏之前本来就是前台」时调。
        SetWindowPos(
          hwnd,
          prevAbove == 0 ? HWND_TOP : prevAbove,
          0,
          0,
          0,
          0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW,
        );
        if (wasForeground) SetForegroundWindow(hwnd);
      }
      for (final hider in overlayHiders) {
        try {
          hider(true);
        } catch (_) {}
      }
    }
  }
}
