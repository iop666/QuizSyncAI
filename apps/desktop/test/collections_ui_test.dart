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
import 'package:quizsync_desktop/state/capture_coordinator.dart';
import 'package:quizsync_desktop/state/collections.dart';
import 'package:quizsync_desktop/ui/home_page.dart';

/// 用户需求 8/9 的桌面侧回归；用户反馈 2/5（本轮）：
/// ① 顶栏显示当前合集名，点击弹出合集切换
/// ② 侧栏只显示当前合集的记录（另一个合集的记录不出现）
/// ③ 多页暂存提示 + 「清空暂存区」；⑤ 暂存条默认不显示
/// ⑥ 导出合集 → 弹「另存为」→ 按所选路径落盘（Markdown + JSON）
///
/// 全部用内存库 + ProviderScope override 驱动，不需要 Windows 平台通道。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late Directory tmp;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
    tmp = Directory.systemTemp.createTempSync('qs-ui-test-');
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Collection> mkCollection(String id, String name) => repo.upsertCollection(
        Collection(
          collectionId: id,
          name: name,
          createdAt: nowMs(),
          updatedAt: nowMs(),
          updatedBy: 'windows-local',
        ),
      );

  Future<void> addSession(String id, String collectionId,
      {int questionCount = 1, int? createdAt}) async {
    final ts = createdAt ?? nowMs();
    await repo.upsertSession(Session(
      sessionId: id,
      collectionId: collectionId,
      imageHash: 'h-$id',
      sourceDevice: 'windows-local',
      status: TaskState.done,
      questionCount: questionCount,
      createdAt: ts,
      updatedAt: ts,
      updatedBy: 'windows-local',
    ));
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    String? activeCollectionId,
    CaptureCoordinator? coordinator,
    Size size = const Size(1200, 800),
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith(
            (ref) => SettingsController(MemoryKeyValueStore())..load()),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        dataRootProvider.overrideWithValue(tmp.path),
        apiKeyReaderProvider.overrideWithValue(() async => null),
        if (activeCollectionId != null)
          activeCollectionIdProvider.overrideWith((ref) => activeCollectionId),
        ...extra,
      ],
      child: MaterialApp(
        theme: QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A),
        home: HomePage(coordinator: coordinator),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// drift 流查询 / Riverpod autoDispose 会留下零延迟 Timer，用例末尾必须换掉整棵树。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('① 顶栏显示当前合集名，点击弹出合集切换', (tester) async {
    await mkCollection('c1', '期末复习');
    await mkCollection('c2', '第三章作业');
    await pumpHome(tester, activeCollectionId: 'c1');

    final pill = find.byKey(const ValueKey('collection-pill'));
    expect(pill, findsOneWidget, reason: '顶栏必须有一个合集药丸');
    expect(find.descendant(of: pill, matching: find.text('期末复习')),
        findsOneWidget, reason: '药丸显示的是当前选中的合集名');

    await tester.tap(pill);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('切换任务合集'), findsOneWidget, reason: '点击药丸弹出合集切换对话框');
    expect(find.text('第三章作业'), findsWidgets, reason: '对话框里能选到另一个合集');

    await unmount(tester);
  });

  // M19 第 2 条：合集删除原来只存在于「启动时的合集选择页」，而那个页面
  // 只有 `active == null` 时才出现——用户进了主界面就再也找不到删除入口。
  // 随时可达的「切换任务合集」弹窗里必须有删除。
  testWidgets('①b 切换弹窗里能删合集：二次确认、不级联删记录', (tester) async {
    await mkCollection('c1', '期末复习');
    await mkCollection('c2', '第三章作业');
    await addSession('s-keep', 'c2', questionCount: 1);
    await pumpHome(tester, activeCollectionId: 'c1');

    await tester.tap(find.byKey(const ValueKey('collection-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('切换任务合集'), findsOneWidget);

    // 取消：什么都不该发生。
    await tester.tap(find.byKey(const ValueKey('picker-delete-c2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('删除合集'), findsOneWidget, reason: '必须先弹二次确认');
    expect(find.textContaining('下有 1 条识别记录'), findsOneWidget,
        reason: '确认框要说清这个合集下有多少记录');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('取消')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await repo.getCollection('c2'), isNotNull, reason: '取消后合集仍在');

    // 确认：合集没了，记录还在（回到「全部记录」）。
    await tester.tap(find.byKey(const ValueKey('picker-delete-c2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('picker-delete-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await repo.getCollection('c2'), isNull, reason: '确认后合集被删');
    expect(await repo.getCollection('c1'), isNotNull, reason: '只删点中的那一个');
    expect(await repo.getSession('s-keep'), isNotNull,
        reason: '删合集不级联删记录（与安卓端/选择页一致）');
    expect(find.text('已删除合集「第三章作业」'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('② 侧栏只显示当前合集的记录，另一个合集的记录不出现', (tester) async {
    await mkCollection('c1', '合集甲');
    await mkCollection('c2', '合集乙');
    await addSession('s-in', 'c1', questionCount: 1);
    await addSession('s-out', 'c2', questionCount: 3);

    await pumpHome(tester, activeCollectionId: 'c1');

    expect(find.text('识别出 1 道题'), findsOneWidget, reason: '当前合集的记录在侧栏');
    expect(find.text('识别出 3 道题'), findsNothing,
        reason: '另一个合集的记录不得出现在侧栏');

    // 切到「全部记录」后两个合集都可见（证明数据源真的换了）。
    await tester.tap(find.text('全部记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('识别出 1 道题'), findsOneWidget);
    expect(find.text('识别出 3 道题'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('③ 多页暂存提示 + 清空暂存区', (tester) async {
    await mkCollection('c1', '合集甲');
    await pumpHome(tester,
        activeCollectionId: 'c1',
        extra: [stagedPageCountProvider.overrideWith((ref) => 2)]);

    expect(find.textContaining('多页暂存：2/6 页'), findsOneWidget,
        reason: '显示「已暂存 N 页 / 上限」');
    // M46 第 1 条：抓满上限自动上传（原来看的是「到 6 页会自动上传」）。
    expect(find.textContaining('抓满 6 张自动上传'), findsOneWidget,
        reason: '说明抓到上限会自动上传识别');
    expect(find.textContaining('按「截屏识别」结束多页立刻上传'), findsOneWidget,
        reason: '没满时按截屏识别键结束并上传（M46 第 1 条）');
    expect(find.textContaining('热键被占用'), findsWidgets,
        reason: '热键为 null 时必须提示可从托盘菜单操作，不能写死按键名');

    final clear = find.byKey(const ValueKey('clear-staging'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 用户反馈 5：暂存归零后整条暂存条消失（默认主界面不显示它）。
    expect(find.textContaining('多页暂存：'), findsNothing,
        reason: '暂存 0 页时暂存条不再显示');
    expect(find.text('已清空多页暂存区'), findsOneWidget, reason: '清空要有反馈');

    await unmount(tester);
  });

  testWidgets('⑤ 多页暂存条默认不显示，攒页后才出现（用户反馈 5）', (tester) async {
    await mkCollection('c1', '合集甲');
    await pumpHome(tester, activeCollectionId: 'c1');

    expect(find.byKey(const ValueKey('clear-staging')), findsNothing,
        reason: '没在攒页时不应出现暂存条');
    expect(find.textContaining('多页暂存：'), findsNothing);

    await unmount(tester);
  });

  testWidgets('⑥ 导出当前合集：二次确认后弹「另存为」并按所选路径落盘', (tester) async {
    await mkCollection('c1', '期末复习');
    await addSession('s-export', 'c1');
    // 用户反馈 2：导出时弹系统「另存为」，测试里用假实现固定输出路径。
    final exportDir = Directory('${tmp.path}/user-picked')..createSync(recursive: true);
    final picked = '${exportDir.path}/我的导出.md';
    savePathChooser = ({
      required String title,
      required String defaultDir,
      required String defaultName,
      required String extension,
      String filterLabel = '文件',
    }) {
      // 默认目录必须指向软件自己的数据目录（用户反馈 2：默认为软件所在目录下）。
      expect(defaultDir, contains('exports'));
      // 用户反馈 2（M12）：交给资源管理器对话框的路径**不能混用正反斜杠** ——
      // `Directory('$root/exports')` 留下正斜杠时 GetSaveFileNameW 直接报
      // FNERR_INVALIDFILENAME 并返回 0，用户看到的就是「点了导出没反应」。
      expect(normalizeForDialog(defaultDir), isNot(contains('/')));
      expect(extension, 'md');
      return picked;
    };
    addTearDown(() => savePathChooser = nativePickSavePath);

    await pumpHome(tester, activeCollectionId: 'c1');

    await tester.tap(find.byKey(const ValueKey('export-collection')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('导出合集「期末复习」？'), findsOneWidget,
        reason: '导出属于耗时操作，必须先二次确认');

    await tester.tap(find.text('选择保存位置…'));
    await tester.pump();
    // 导出要真的写文件：widget 测试的假时钟不会自己推进 dart:io 的真实异步，
    // 交替「pump 刷微任务 + runAsync 给真实事件循环时间」把整条链路跑完。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
    await tester.pump(const Duration(milliseconds: 300));

    final md = File(picked);
    expect(md.existsSync(), isTrue, reason: 'Markdown 必须写到用户选的位置');
    expect(File('${exportDir.path}/我的导出.json').existsSync(), isTrue,
        reason: '同名 JSON 一起写出');
    expect(md.readAsStringSync(), contains('任务合集：期末复习'));
    expect(find.textContaining('已导出 1 条记录：'), findsOneWidget);
    expect(find.textContaining(md.path), findsOneWidget,
        reason: 'SnackBar 要给出完整路径（与磁盘上的真实路径一致）');
    expect(find.text('打开所在目录'), findsOneWidget,
        reason: '给一个打开所在目录的动作');

    await unmount(tester);
  });

  testWidgets('⑧ 多页会话在侧栏带「N 页」标记，单页会话没有', (tester) async {
    await mkCollection('c1', '合集甲');
    await addSession('s-one', 'c1', questionCount: 1);
    await addSession('s-multi', 'c1', questionCount: 2);
    await repo.setSessionImages('s-multi', ['h-multi-a', 'h-multi-b', 'h-multi-c']);

    await pumpHome(tester, activeCollectionId: 'c1');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('3 页'), findsOneWidget, reason: '多页会话要显示页数');
    expect(find.text('1 页'), findsNothing, reason: '单页会话不加页数标记');

    await unmount(tester);
  });

  testWidgets('⑨ 协调器接线：暂存回调接上，识别完成后跳到新会话', (tester) async {
    await mkCollection('c1', '合集甲');
    await addSession('s-old', 'c1', createdAt: nowMs());
    await addSession('s-new', 'c1', createdAt: nowMs() - 5000);

    final coordinator = CaptureCoordinator(
      refOf: () => throw StateError('本用例不触发采集'),
      contextOf: () => throw StateError('本用例不触发采集'),
      imageDir: tmp.path,
    );
    await pumpHome(tester,
        activeCollectionId: 'c1', coordinator: coordinator);

    expect(coordinator.onStagingChanged, isNotNull,
        reason: '主界面必须接上暂存区变化回调');
    expect(coordinator.onSessionReady, isNotNull,
        reason: '主界面必须接上「识别完成」回调');
    // 默认停在最新一条。
    expect(find.byKey(const ValueKey('nav-position')), findsOneWidget);
    expect(find.text('第 1 / 2 条记录'), findsOneWidget);

    coordinator.onStagingChanged!();
    await tester.pump();
    // 用户反馈 5：暂存 0 页时暂存条不渲染（回调本身仍然被调用）。
    expect(find.textContaining('多页暂存：'), findsNothing);

    // 模拟识别完成 → 跳到刚生成的那条（列表里更旧的一条）。
    coordinator.onSessionReady!('s-new');
    await tester.pump();
    expect(find.text('第 2 / 2 条记录'), findsOneWidget,
        reason: '识别完成后要选中新会话');

    await unmount(tester);
  });

  testWidgets('⑩ 最小窗口 860x520 + 长合集名：顶栏不溢出', (tester) async {
    await mkCollection('c1', '期末复习资料第二册第三章课后习题汇总');
    await addSession('s-narrow', 'c1', questionCount: 2);

    await pumpHome(tester,
        activeCollectionId: 'c1', size: const Size(860, 520));

    // 溢出会以异常形式抛出（黄黑条 + RenderFlex overflowed）。
    expect(tester.takeException(), isNull, reason: '窄窗口 + 长合集名不得出现布局溢出');
    expect(find.byKey(const ValueKey('collection-pill')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-collection')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('⑫ 手机发起的识别：主界面自动跳到那次识别的会话（用户反馈 12）', (tester) async {
    await mkCollection('c1', '合集甲');
    await addSession('s-old', 'c1', createdAt: nowMs());
    await addSession('s-from-phone', 'c1', createdAt: nowMs() - 5000);
    addTearDown(() => remoteTaskSession.value = null);

    await pumpHome(tester, activeCollectionId: 'c1');
    // 默认停在最新一条。
    expect(find.text('第 1 / 2 条记录'), findsOneWidget);

    // 服务端收到手机任务时会写这个 notifier（外壳同时把窗口带到前台）。
    remoteTaskSession.value = 's-from-phone';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第 2 / 2 条记录'), findsOneWidget,
        reason: '手机发起的识别要自动切到那次识别（Windows 端显示识别界面）');

    await unmount(tester);
  });

  testWidgets('⑪ 攒页时窄窗口的暂存条不溢出（用户反馈 5 显示时才出现）', (tester) async {
    await mkCollection('c1', '期末复习资料第二册第三章课后习题汇总');
    await addSession('s-narrow', 'c1', questionCount: 2);

    await pumpHome(tester,
        activeCollectionId: 'c1',
        size: const Size(860, 520),
        extra: [stagedPageCountProvider.overrideWith((ref) => 2)]);

    expect(tester.takeException(), isNull, reason: '暂存条显示时也不得溢出');
    expect(find.byKey(const ValueKey('clear-staging')), findsOneWidget);

    await unmount(tester);
  });
}
