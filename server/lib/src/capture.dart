import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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

/// GDI BitBlt 截屏（照搬主项目 `apps/desktop/lib/services/screen_capture.dart`
/// 的实现，去掉「隐藏应用窗口」那一段 —— Server 没有 GUI 窗口）：
/// - 截取**鼠标所在显示器**的全屏；
/// - Per-Monitor DPI V2：采集线程临时切换 DPI 感知上下文，保证物理像素坐标。
class ScreenCapture {
  /// 截取鼠标所在显示器；失败抛异常。
  ///
  /// **刻意不隐藏命令行窗口**（Desktop 版会藏主窗口，Server 不这么做）：
  /// 实测 `ShowWindow(SW_HIDE)` + `SetWindowPos(..., SWP_SHOWWINDOW)` 会把控制台
  /// 窗口变回前台，之后**合成按键就再也进不来**（UIPI/前台窗口问题），表现为
  /// 「第一次截图后 F8/F9 全部失灵」，而热键本身是好的。代价只是：如果用户正
  /// 盯着命令行窗口按热键，那点日志文字会被拍进图里 —— 而 prompt 明确要求 AI
  /// 忽略界面元素，这个代价可以接受。
  CapturedScreen captureCursorMonitor() {
    return using((arena) {
      // Per-Monitor DPI V2：坐标一律物理像素。
      final oldDpi = SetThreadDpiAwarenessContext(
          DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
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
      final pixels = Uint8List(w * h * 4)
        ..setRange(0, w * h * 4, pPixels.asTypedList(w * h * 4));
      return CapturedScreen(width: w, height: h, bgra: pixels);
    } finally {
      SelectObject(hdcMem, oldBitmap);
      DeleteObject(hBitmap);
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
    }
  }

}
