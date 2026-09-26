import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/ui/collection_picker_page.dart';

/// 用户需求 8（原话「每次打开都要选择合集」）的桌面侧回归：
/// 1. 已经有合集时**不会自动进主界面**，必须点「进入」；
/// 2. 上次用过的合集排首位并带「上次使用」药丸（方便直接点，但不会自动进）。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
  });

  tearDown(() async => db.close());

  Future<void> mkCollection(String id, String name, {int? createdAt}) {
    final ts = createdAt ?? nowMs();
    return repo.upsertCollection(Collection(
      collectionId: id,
      name: name,
      createdAt: ts,
      updatedAt: ts,
      updatedBy: 'windows-local',
    ));
  }

  Future<void> pumpGate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith(
            (ref) => SettingsController(MemoryKeyValueStore())..load()),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        apiKeyReaderProvider.overrideWithValue(() async => null),
      ],
      child: const MaterialApp(
        home: CollectionGate(
          child: Scaffold(body: Center(child: Text('主界面占位'))),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('有合集时也不会自动进主界面，点「进入」才进', (tester) async {
    await mkCollection('c1', '合集甲');
    await pumpGate(tester);

    expect(find.text('选择任务合集'), findsOneWidget, reason: '每次打开都停在合集选择页');
    expect(find.text('主界面占位'), findsNothing, reason: '不得自动进入上次的合集');

    await tester.tap(find.text('进入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('主界面占位'), findsOneWidget, reason: '点「进入」后才进主界面');
    await unmount(tester);
  });

  testWidgets('上次使用的合集排首位并带「上次使用」药丸', (tester) async {
    // 刻意让「上次使用」的合集创建得更早（默认排序里更靠后）。
    await mkCollection('c-last', '上次的合集', createdAt: nowMs() - 5000);
    await mkCollection('c-new', '新建的合集');
    await repo.setSetting(kLastCollectionKey, 'c-last');

    await pumpGate(tester);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('上次使用'), findsOneWidget, reason: '上次用过的合集要标出来');
    final lastY =
        tester.getTopLeft(find.byKey(const ValueKey('collection-c-last'))).dy;
    final newY =
        tester.getTopLeft(find.byKey(const ValueKey('collection-c-new'))).dy;
    expect(lastY, lessThan(newY), reason: '上次使用的合集排首位');

    // 排首位不等于自动进入：选择页还在，仍然要手动点「进入」。
    expect(find.text('选择任务合集'), findsOneWidget);
    expect(find.text('主界面占位'), findsNothing);
    await unmount(tester);
  });
}
