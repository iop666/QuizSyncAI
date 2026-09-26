// 诊断脚本：反复注册/注销三个全局热键，打印每次的 Win32 结果。
// 用途：定位「改热键 / 恢复默认后偶发 registration failed」的真正原因。
// 运行：dart run tool/hotkey_probe.dart
import 'dart:io';

import 'package:quizsync_server/src/hotkey_service.dart';
import 'package:quizsync_server/src/hotkeys.dart';

Future<void> main() async {
  final svc = HotkeyService(trace: (m) => print('[trace] $m'));
  final slots = <(String, HotkeySpec)>[
    ('capture', parseHotkey('F6')),
    ('append', parseHotkey('F8')),
    ('finish', parseHotkey('F9')),
  ];

  Future<void> registerAll(String tag) async {
    for (final (slot, spec) in slots) {
      final ok = await svc.register(
        slot: slot,
        vk: spec.vk,
        nativeModifiers: spec.modifiers,
        onTrigger: () {},
      );
      print('$tag $slot ${spec.label} ok=$ok err=${svc.lastErrorCode}');
    }
  }

  print('--- 第一轮：全新注册');
  await registerAll('fresh');

  for (var round = 1; round <= 3; round++) {
    print('--- 第 $round 轮：unregister() 全部 + 立即重注册');
    await svc.unregister();
    await registerAll('round$round');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  print('--- 换个键再换回来');
  await svc.register(
      slot: 'capture',
      vk: parseHotkey('Ctrl+Alt+F9').vk,
      nativeModifiers: parseHotkey('Ctrl+Alt+F9').modifiers,
      onTrigger: () {});
  print('capture Ctrl+Alt+F9 ok');
  for (var i = 0; i < 3; i++) {
    await svc.unregister();
    await registerAll('swap$i');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  await svc.dispose();
  exit(0);
}
