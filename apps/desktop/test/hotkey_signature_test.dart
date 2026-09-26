import 'dart:convert';

import 'package:flutter/services.dart' show PhysicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/state/app_scope.dart';

/// 用户反馈 14：改任意一个多页热键都必须能触发「重新注册全部热键」。
///
/// 外壳用 [hotkeySettingsSignature] 判断热键设置有没有变；原来的代码只监听
/// 第一个槽位，改「添加页面 / 结束多页识别」时完全不会重新注册。
/// M46 第 1 条后只剩两个槽位（截屏识别 / 多页模式），结论不变。
void main() {
  String jsonOf(HotKey hk) => jsonEncode(hk.toJson());

  group('热键设置指纹（用户反馈 14）', () {
    test('两个槽位任意一个变化都会改变指纹', () {
      const base = AppSettings();
      final capture = base.copyWith(
          hotkeyJson: jsonOf(HotKey(
              key: PhysicalKeyboardKey.keyQ,
              modifiers: [HotKeyModifier.control, HotKeyModifier.alt])));
      final multipage = base.copyWith(
          multipageHotkeyJson: jsonOf(HotKey(
              key: PhysicalKeyboardKey.keyA,
              modifiers: [HotKeyModifier.control, HotKeyModifier.alt])));

      final s0 = hotkeySettingsSignature(base);
      expect(hotkeySettingsSignature(capture), isNot(s0),
          reason: '截屏识别热键变化必须被察觉');
      expect(hotkeySettingsSignature(multipage), isNot(s0),
          reason: '「多页模式」热键变化必须被察觉（这就是原来的 bug）');
      // 两个槽位互换内容也不能算「没变」：指纹按槽位拼接。
      expect(hotkeySettingsSignature(capture),
          isNot(hotkeySettingsSignature(multipage)));
    });

    test('与热键无关的设置变化不会触发重新注册', () {
      const base = AppSettings();
      final s0 = hotkeySettingsSignature(base);
      expect(hotkeySettingsSignature(base.copyWith(fontSize: 22)), s0);
      expect(hotkeySettingsSignature(base.copyWith(theme: ThemeMode2.dark)), s0);
      expect(hotkeySettingsSignature(base.copyWith(listenPort: 9999)), s0);
    });

    test('清空自定义热键同样算变化（要回退到默认键）', () {
      final withCustom = const AppSettings().copyWith(
          multipageHotkeyJson: jsonOf(HotKey(
              key: PhysicalKeyboardKey.keyZ,
              modifiers: [HotKeyModifier.control, HotKeyModifier.alt])));
      final cleared = withCustom.copyWith(clearMultipageHotkey: true);
      expect(hotkeySettingsSignature(withCustom),
          isNot(hotkeySettingsSignature(cleared)));
    });
  });
}
