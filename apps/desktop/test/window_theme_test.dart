import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/services/window_theme.dart';

/// Windows 标题栏跟随主题（用户反馈 7 +「Windows 也没改」）。
///
/// 平台调用没法在单测里断言（需要真窗口），所以这里锁住**纯逻辑**部分：
/// COLORREF 的通道顺序（写错会偏色）与属性号。真实效果由 `build_all` 之后的
/// 冒烟脚本用 `DwmGetWindowAttribute` 复核（见 `docs/manual-test-android.md` 第 23 项）。
void main() {
  group('COLORREF 通道顺序（DWM 要的是 0x00BBGGRR）', () {
    test('纯色分别落在正确的字节上', () {
      expect(colorRefOf(const Color(0xFFFF0000)), 0x000000FF); // 红 → 最低字节
      expect(colorRefOf(const Color(0xFF00FF00)), 0x0000FF00); // 绿
      expect(colorRefOf(const Color(0xFF0000FF)), 0x00FF0000); // 蓝 → 最高字节
    });

    test('品牌色与白色：和 Flutter 里的取值对得上', () {
      // 纯白/纯黑是最容易发现顺序错误的两端。
      expect(colorRefOf(const Color(0xFFFFFFFF)), 0x00FFFFFF);
      expect(colorRefOf(const Color(0xFF000000)), 0x00000000);
      // #16A34A：r=0x16 g=0xA3 b=0x4A → COLORREF = 0x4A A3 16
      expect(colorRefOf(const Color(0xFF16A34A)), 0x004AA316);
    });

    test('忽略 alpha（DWM 这几项不吃透明度）', () {
      expect(colorRefOf(const Color(0x00FFFFFF)), colorRefOf(const Color(0xFFFFFFFF)));
      expect(colorRefOf(const Color(0x8016A34A)), colorRefOf(const Color(0xFF16A34A)));
    });
  });

  test('DWM 属性号与 MSDN 一致（20 为现代系统、19 为 Win10 1809 回退）', () {
    expect(dwmwaUseImmersiveDarkMode, 20);
    expect(dwmwaUseImmersiveDarkModeLegacy, 19);
    expect(dwmwaCaptionColor, 35);
    expect(dwmwaTextColor, 36);
    expect(dwmwaBorderColor, 34);
  });

  test('找不到窗口时不做任何事（返回 0，不抛异常）', () {
    expect(
        applyWindowChromeTheme(0, brightness: Brightness.dark), 0);
  });
}
