import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:quizsync_core/quizsync_core.dart' show AppLogger;
import 'package:win32/win32.dart';

import '../state/app_info.dart' show kAppName;

// Windows 窗口标题栏（以及 Win11 的窗口边框）跟随应用主题。
//
// **为什么不用 `windowManager.setBrightness`**：它在 Windows 端的实现是
//   BOOL enable_dark_mode = light_mode == 0 && brightness == "dark";
//   // window_manager-0.4.3/windows/window_manager.cpp:1034
// 其中 `light_mode` 读的是**系统**的 `AppsUseLightTheme`：它把「应用想要的
// 深色」和「系统当前是不是深色」做了个 AND。系统是浅色时，无论应用怎么设，
// `enable_dark_mode` 永远是 FALSE —— 标题栏永远白着。用户反馈「切了深色
// Windows 这边也不跟着变」就是这个原因（本机 `AppsUseLightTheme = 1`，
// 必然复现，与方法调用时机无关）。
//
// 所以这里自己调 `DwmSetWindowAttribute`：只看应用主题，不看系统设置。

/// DWM 属性号（MSDN：DWMWA_USE_IMMERSIVE_DARK_MODE）。
const int dwmwaUseImmersiveDarkMode = 20;

/// Win10 1809 用的是 19，之后改成 20；两个都试一遍。
const int dwmwaUseImmersiveDarkModeLegacy = 19;

/// Win11 22000+：窗口边框 / 标题栏底色 / 标题文字色。
const int dwmwaBorderColor = 34;
const int dwmwaCaptionColor = 35;
const int dwmwaTextColor = 36;

/// Flutter 的 [Color] → Win32 的 `COLORREF`（`0x00BBGGRR`，**BGR 顺序**）。
/// DWM 的 34/35/36 号属性收的就是这个格式；写错会得到诡异的偏色。
int colorRefOf(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xff;
  final g = (argb >> 8) & 0xff;
  final b = argb & 0xff;
  return (b << 16) | (g << 8) | r;
}

/// 找一个按标题定位的顶层窗口；找不到返回 0。
int findAppWindow(String title) {
  final ptr = title.toNativeUtf16();
  try {
    return FindWindow(nullptr, ptr);
  } finally {
    calloc.free(ptr);
  }
}

/// 本应用的主窗口现在是不是**前台**窗口（M31 热键闸门用）。
///
/// 一次判断同时覆盖三种「用户其实不在热键设置页里」的情况：窗口收进托盘
/// （不是前台）、窗口最小化（不是前台）、用户切到了别的程序（前台是别人）。
/// 这三种情况热键都必须照常生效 —— 用「进/出页面时改一个 bool」是做不出这个
/// 语义的（M30 就这么把热键锁死过）。
bool appWindowIsForeground() {
  final hwnd = findAppWindow(kAppName);
  return hwnd != 0 && GetForegroundWindow() == hwnd;
}

/// 应用标题栏主题。返回成功应用的项数（0 = 系统完全不支持，只记日志）。
///
/// [caption]/[text]/[border] 传应用主题里的颜色，标题栏就能和界面里的顶栏
/// 完全同色；不传则只切深浅（老系统只支持这一项）。
int applyWindowChromeTheme(
  int hwnd, {
  required Brightness brightness,
  Color? caption,
  Color? text,
  Color? border,
}) {
  if (hwnd == 0) return 0;
  var applied = 0;
  final dark = brightness == Brightness.dark;

  // 1. 深浅模式：决定标题文字/系统图标用亮色还是暗色。
  final value = calloc<Uint32>();
  try {
    value.value = dark ? 1 : 0;
    var hr = DwmSetWindowAttribute(
        hwnd, dwmwaUseImmersiveDarkMode, value.cast(), sizeOf<Uint32>());
    if (hr != 0) {
      // Win10 1809 用 19；再失败就说明系统太老，下面几项也不会支持。
      hr = DwmSetWindowAttribute(hwnd, dwmwaUseImmersiveDarkModeLegacy,
          value.cast(), sizeOf<Uint32>());
    }
    if (hr != 0) {
      AppLogger.instance
          .warn('window', '标题栏深浅设置失败（DWM 0x${hr.toRadixString(16)}）');
      return 0;
    }
    applied++;

    // 2. Win11 的标题栏配色（Win10 返回 E_INVALIDARG，忽略即可）。
    void tryColor(int attr, Color? color) {
      if (color == null) return;
      value.value = colorRefOf(color) & 0xffffffff;
      final r = DwmSetWindowAttribute(hwnd, attr, value.cast(), sizeOf<Uint32>());
      if (r == 0) applied++;
    }

    tryColor(dwmwaCaptionColor, caption);
    tryColor(dwmwaTextColor, text);
    tryColor(dwmwaBorderColor, border);
    return applied;
  } catch (e) {
    AppLogger.instance.warn('window', '标题栏主题设置失败：$e');
    return applied;
  } finally {
    calloc.free(value);
  }
}
