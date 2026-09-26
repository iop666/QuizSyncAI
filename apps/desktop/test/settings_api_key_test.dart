import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/services/secure_store.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/state/settings.dart';
import 'package:quizsync_desktop/ui/home_page.dart' show dataRootProvider;
import 'package:quizsync_desktop/ui/settings_page.dart';

void main() {
  test('WindowsSecureStore DPAPI 往返：write → read → delete（真机同路径）', () async {
    final path =
        '${Directory.systemTemp.path}/qs-test-secure-${DateTime.now().microsecondsSinceEpoch}.bin';
    addTearDown(() {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    });
    final store = WindowsSecureStore(path);

    expect(await store.read('ai_api_key'), isNull, reason: '文件不存在时按空表处理');
    await store.write('ai_api_key', 'sk-test-1234567890');
    expect(await store.read('ai_api_key'), 'sk-test-1234567890',
        reason: 'DPAPI 加密落盘后可解密读回');
    await store.write('other', 'v2');
    expect(await store.read('ai_api_key'), 'sk-test-1234567890', reason: '多键共存');
    await store.delete('ai_api_key');
    expect(await store.read('ai_api_key'), isNull);
    expect(File(path).existsSync(), isTrue, reason: '加密文件不应是明文 JSON');
    final bytes = await File(path).readAsBytes();
    expect(String.fromCharCodes(bytes).contains('sk-test'), isFalse,
        reason: '密文里不得出现明文 Key');
  });

  /// 打开设置页并切到「API 配置」。返回 (settings, 读存储的闭包)。
  Future<SettingsController> openApiPage(
    WidgetTester tester, {
    required String? Function() readStored,
    required void Function(String) writeStored,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = QuizSyncDb(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CoreRepository(db: db, deviceId: 'windows-local');
    final settings = SettingsController(MemoryKeyValueStore());
    await settings.load();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => settings),
        apiKeyReaderProvider.overrideWithValue(() async => readStored()),
        apiKeyWriterProvider.overrideWithValue((k) async => writeStored(k)),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        dataRootProvider.overrideWithValue(Directory.systemTemp.path),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();
    // 设置页是左导航分类，API Key 在「API 配置」里。
    await tester.tap(find.byKey(const ValueKey('settings-nav-api')));
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('settings-api-key-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-api-key-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('设置页：首次保存 API Key → 先弹隐私告知，确认后才写入', (tester) async {
    String? stored;
    final settings = await openApiPage(tester,
        readStored: () => stored, writeStored: (k) => stored = k);

    await tester.enterText(
        find.byKey(const ValueKey('settings-api-key')), 'sk-my-key-9876');
    await tapSave(tester);

    // M34 第 1 条：隐私告知**只在首次保存 API Key 时**提示。
    expect(find.text('隐私告知'), findsOneWidget, reason: '首次保存要先看隐私告知');
    expect(stored, isNull, reason: '没确认之前不能写入');
    expect(settings.privacyAcknowledged, isFalse);

    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();

    expect(stored, 'sk-my-key-9876', reason: '确认后必须写入');
    expect(settings.privacyAcknowledged, isTrue, reason: '确认要落库，只提示一次');
    expect(find.textContaining('****9876'), findsOneWidget, reason: '保存后回显尾 4 位');
    expect(find.text('API Key 已保存'), findsOneWidget, reason: '给出保存成功反馈');
  });

  testWidgets('设置页：隐私告知点「暂不使用」→ 不保存这个 Key', (tester) async {
    String? stored;
    final settings = await openApiPage(tester,
        readStored: () => stored, writeStored: (k) => stored = k);

    await tester.enterText(
        find.byKey(const ValueKey('settings-api-key')), 'sk-never-saved');
    await tapSave(tester);
    await tester.tap(find.text('暂不使用'));
    await tester.pumpAndSettle();

    expect(stored, isNull, reason: '拒绝告知就不能写入');
    expect(settings.privacyAcknowledged, isFalse);
    expect(find.textContaining('没有保存'), findsOneWidget, reason: '要明确告诉用户没保存');
  });

  testWidgets('设置页：已确认过隐私告知 → 保存不再弹窗，回车路径也可用', (tester) async {
    String? stored;
    final settings = await openApiPage(tester,
        readStored: () => stored, writeStored: (k) => stored = k);
    await settings.acknowledgePrivacy();

    await tester.enterText(
        find.byKey(const ValueKey('settings-api-key')), 'sk-enter-key-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('隐私告知'), findsNothing, reason: '确认过就不再打扰');
    expect(stored, 'sk-enter-key-1', reason: '回车（onFieldSubmitted）保存路径保持可用');

    // 再换一个 Key 也不弹。
    await tester.enterText(
        find.byKey(const ValueKey('settings-api-key')), 'sk-second-key');
    await tapSave(tester);
    expect(find.text('隐私告知'), findsNothing);
    expect(stored, 'sk-second-key');
  });
}
