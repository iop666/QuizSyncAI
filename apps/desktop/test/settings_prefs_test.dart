import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/services/shell_open.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/state/collections.dart';
import 'package:quizsync_desktop/ui/home_page.dart' show dataRootProvider;
import 'package:quizsync_desktop/ui/settings_page.dart';

/// 设置页的本次改动回归：
/// ④ 主题三态存在、accent 配色选择已移除
/// ⑤ 图片缓存上限 / 多页页数上限可改并持久化（硬上限 6）
/// ⑦ 设置页也能导出合集（弹「另存为」→ 按所选路径落盘）
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late MemoryKeyValueStore store;
  late SettingsController settings;
  late Directory tmp;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
    store = MemoryKeyValueStore();
    settings = SettingsController(store);
    await settings.load();
    tmp = Directory.systemTemp.createTempSync('qs-settings-test-');
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpSettings(WidgetTester tester,
      {String? activeCollectionId}) async {
    // 高一点的视口：设置页整页可见，避免拖动/点击被滚出屏幕干扰。
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => settings),
        apiKeyReaderProvider.overrideWithValue(() async => null),
        apiKeyWriterProvider.overrideWithValue((k) async {}),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        dataRootProvider.overrideWithValue(tmp.path),
        if (activeCollectionId != null)
          activeCollectionIdProvider.overrideWith((ref) => activeCollectionId),
      ],
      child: const MaterialApp(home: SettingsPage()),
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

  /// 切到某个设置分类（M9：设置页改成左导航 + 右内容，
  /// 每个分类的控件只在选中它时才挂在树上）。
  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('settings-nav-$tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('④ 设置页有主题三态，且不存在 accent 配色选择', (tester) async {
    await pumpSettings(tester);
    // M32 用户需求 5：设置页第一项改成「使用说明」，所以先切到显示设置。
    await openTab(tester, 'display');

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.byType(AccentPicker), findsNothing,
        reason: '按用户要求删除主题配色选择 UI');

    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(settings.app.theme, ThemeMode2.dark, reason: '三态选择真的写进设置');
    expect(await store.read('theme'), 'dark', reason: '主题模式要落库');

    await unmount(tester);
  });

  testWidgets('⑤ 设置页能改图片缓存上限与多页页数上限，并持久化', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, 'recognition');

    // 默认 60 张；「不设限」= 0。
    expect(find.textContaining('最多保留 60 张'), findsOneWidget);
    await tester.tap(find.text('不设限'));
    await tester.pump();
    expect(settings.app.imageCacheLimit, 0, reason: '「不设限」写成 0');
    expect(find.textContaining('当前：不设限'), findsOneWidget);

    // 多页上限拖到最大（用户反馈 9：硬上限就是 6 张，不是 12）。
    await tester.drag(
        find.byKey(const ValueKey('settings-multi-page')), const Offset(800, 0));
    await tester.pump();
    expect(settings.app.multiPageLimit, kHardMaxPagesPerTask,
        reason: '滑块能改多页上限（1..$kHardMaxPagesPerTask）');
    expect(find.text('6 页'), findsOneWidget);

    // 持久化：同一个存储上新建控制器读回同样的值。
    final reloaded = SettingsController(store);
    await reloaded.load();
    expect(reloaded.app.imageCacheLimit, 0);
    expect(reloaded.app.multiPageLimit, kHardMaxPagesPerTask);

    await unmount(tester);
  });

  testWidgets('⑤b 热键设置页：两个槽位都在，没注册上时不假装成功', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, 'hotkey');
    // 两个用途各自一行（M46 第 1 条：热键只留截屏识别 / 多页模式）。
    for (final name in ['capture', 'multipage']) {
      expect(find.byKey(ValueKey('settings-hotkey-$name')), findsOneWidget);
    }
    expect(find.text('截屏识别'), findsOneWidget, reason: '第一个槽位的分组标题');
    expect(find.text('截取屏幕并识别'), findsOneWidget, reason: '第一个槽位那一行');
    expect(find.text('多页模式'), findsNWidgets(2),
        reason: '第二个槽位：分组标题 + 那一行各一次');
    // 测试环境里没有真实注册（provider 为空）→ 只能说「正在注册…」，
    // 绝不能编一个看起来生效了的键出来。
    expect(find.text('正在注册…'), findsNWidgets(2));
    // 用户反馈 10：「重新注册」按钮换成「恢复默认」（默认没设过自定义键时禁用）。
    expect(find.byKey(const ValueKey('settings-hotkey-restore-defaults')),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('⑦ 设置页导出合集：二次确认 → SnackBar 给出路径', (tester) async {
    await repo.upsertCollection(Collection(
      collectionId: 'c-set',
      name: '第三章作业',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
    await repo.upsertSession(Session(
      sessionId: 's-set',
      collectionId: 'c-set',
      imageHash: 'h-set',
      sourceDevice: 'windows-local',
      status: TaskState.done,
      questionCount: 1,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
    await pumpSettings(tester, activeCollectionId: 'c-set');
    await openTab(tester, 'data');

    expect(find.text('当前合集：第三章作业'), findsOneWidget);
    final exportBtn = find.byKey(const ValueKey('settings-export-collection'));
    expect(exportBtn, findsOneWidget);

    // 用户反馈 2：导出弹「另存为」，测试注入固定路径 + 断言默认目录在软件目录下。
    final pickedPath = '${tmp.path}/user-picked/导出合集.md';
    Directory('${tmp.path}/user-picked').createSync(recursive: true);
    savePathChooser = ({
      required String title,
      required String defaultDir,
      required String defaultName,
      required String extension,
      String filterLabel = '文件',
    }) {
      expect(defaultDir, contains('exports'), reason: '默认目录 = 软件数据目录下的 exports/');
      // M12：混用正反斜杠会让资源管理器对话框报 FNERR_INVALIDFILENAME。
      expect(normalizeForDialog(defaultDir), isNot(contains('/')),
          reason: '交给「另存为」的路径必须归一化成纯反斜杠');
      return pickedPath;
    };
    addTearDown(() => savePathChooser = nativePickSavePath);

    await tester.tap(exportBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('导出合集「第三章作业」？'), findsOneWidget);

    await tester.tap(find.text('选择保存位置…'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // 用户反馈 2：导出会弹「另存为」（测试注入固定路径），Markdown 与 JSON 一起写出。
    final md = File(pickedPath);
    expect(md.existsSync(), isTrue, reason: '按用户选择的路径落 Markdown');
    expect(File('${File(pickedPath).parent.path}/导出合集.json').existsSync(), isTrue,
        reason: '除 Markdown 外还要落一份 JSON');
    expect(find.textContaining('已导出 1 条记录：'), findsOneWidget);

    await unmount(tester);
  });
}
