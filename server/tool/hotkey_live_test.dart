// 诊断脚本：注册命令行给出的键，打印每一次真实触发（带时间戳），跑一段时间。
//
// 用法：dart run tool/hotkey_live_test.dart F4 F5          （观察用）
//       dart run tool/hotkey_live_test.dart F6 F8 F9       （与默认值一致）
//
// 目的：判断「按了热键不触发」到底是本进程的问题，还是合成按键/系统层面的问题。
import 'dart:io';

import 'package:quizsync_server/src/hotkey_service.dart';
import 'package:quizsync_server/src/hotkeys.dart';

Future<void> main(List<String> args) async {
  final names = args.isEmpty ? ['F6', 'F8', 'F9'] : args;
  final seconds = int.tryParse(Platform.environment['HOTKEY_TEST_SECONDS'] ?? '') ?? 30;
  final svc = HotkeyService(trace: (m) => print('[trace] $m'));
  for (var i = 0; i < names.length; i++) {
    final spec = parseHotkey(names[i]);
    final slot = 'slot$i';
    final ok = await svc.register(
      slot: slot,
      vk: spec.vk,
      nativeModifiers: spec.modifiers,
      onTrigger: () => print('>>> FIRED $slot ${spec.label} '
          'at ${DateTime.now().toIso8601String()}'),
    );
    print('register $slot ${spec.label} -> $ok (err=${svc.lastErrorCode})');
  }
  print('请按键：${names.join(' / ')}（$seconds 秒）…');
  await Future<void>.delayed(Duration(seconds: seconds));
  await svc.dispose();
  exit(0);
}
