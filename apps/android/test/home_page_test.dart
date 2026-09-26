import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show AccentPicker;

import 'package:quizsync_android/state/app_info.dart';
import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/state/providers.dart';
import 'package:quizsync_android/ui/current_task_page.dart';
import 'package:quizsync_android/ui/home_page.dart';
import 'package:quizsync_android/ui/recognition_settings_page.dart'
    show kRecognitionSlowNote;

import 'support.dart';

/// Android 主壳（用户需求 6/7/8/11/12/13）的界面回归测试。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;
  late List<String> channelLog;

  const pairing = PairingInfo(
    host: '127.0.0.1',
    port: 8765,
    token: 't',
    serverDeviceId: 'server-1',
    serverName: '测试电脑',
  );

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
    channelLog = installCaptureChannelMock();
  });

  tearDown(() async {
    clearCaptureChannelMock();
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester,
      {PairingInfo? info,
      FakeHostGateway? gateway,
      ApiClient Function(String baseUrl)? pairingClient}) async {
    await tester.pumpWidget(wrapApp(
      app,
      gateway: gateway,
      pairingClient: pairingClient,
      home: AndroidHomePage(pairing: info),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Collection sampleCollection() => Collection(
        collectionId: 'c1',
        name: '期末复习',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'server-1',
      );

  testWidgets('底部三标签，默认打开「当前任务」', (tester) async {
    await pumpHome(tester);

    expect(find.byKey(const ValueKey('tab-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-settings')), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0, reason: '默认打开当前任务');

    // 未配对时当前任务页显示的是「与电脑的连接状态」，而不是历史列表。
    expect(find.byKey(const ValueKey('host-status-text')), findsOneWidget);
    expect(find.text('未配对'), findsWidgets);
    expect(find.text('还没有识别记录'), findsNothing);
    await unmount(tester);
  });

  testWidgets('当前任务页不出现任何识别模块 UI（用户需求 1）', (tester) async {
    // 直接单独渲染当前任务页：IndexedStack 里三个 tab 同时存在于 widget 树中，
    // 在主页上断言「没有识别模块字样」会被设置页的内容干扰。
    expect(app.settings.app.androidRecognitionEnabled, isFalse);

    await tester.pumpWidget(wrapApp(
      app,
      home: const Scaffold(body: CurrentTaskPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 识别模块开关 / 权限引导 / 一键开启 / 识别模块设置入口全都不在。
    expect(find.text('识别模块已关闭'), findsNothing);
    expect(find.byKey(const ValueKey('enable-recognition')), findsNothing);
    expect(find.byKey(const ValueKey('open-recognition-settings')), findsNothing);
    expect(find.textContaining('识别模块'), findsNothing);
    expect(find.textContaining('悬浮球'), findsNothing);
    expect(find.textContaining('权限'), findsNothing);
    // 页面主体：一行连接状态 + 电脑任务结果。
    expect(find.byKey(const ValueKey('host-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('host-status-text')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('当前任务页：进行中显示「N 张图片识别中…」，完成显示答案', (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    await pumpHome(
        tester,
        info: pairing,
        gateway: FakeHostGateway(
          activeCollectionId: 'c1',
          activeCollectionName: '期末复习',
          availableCollections: [sampleCollection()],
        ));
    await tester.pump(const Duration(milliseconds: 300));

    final container = ProviderScope.containerOf(
        tester.element(find.byType(CurrentTaskPage)));

    // 主机本地截屏起的任务：本地还没有这条会话，也能显示页数。
    container.read(activeTaskProvider.notifier).update(
          taskId: 't-host',
          status: TaskState.analyzing,
          sessionId: 's-host',
          imageCount: 4,
        );
    await tester.pump();
    expect(find.text('4 张图片识别中…'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-running')), findsOneWidget);

    // 结果到达：答案直接显示在当前任务页（用户需求 1）。
    await app.repo.upsertSession(Session(
      sessionId: 's-host',
      collectionId: 'c1',
      imageHash: 'h-host',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await app.repo.upsertQuestion(Question(
      questionId: 'q-host',
      sessionId: 's-host',
      ordinal: 0,
      questionNo: '12',
      stem: '主机识别出来的题干',
      type: QuestionType.single,
      choice: const ['B'],
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    container.read(activeTaskProvider.notifier).done(sessionId: 's-host');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('task-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-answer-q-host')), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-result')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('WS 事件（无需手动下拉）就能让当前任务页出现进度与结果', (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    late WidgetRef capturedRef;
    await tester.pumpWidget(wrapApp(
      app,
      gateway: FakeHostGateway(
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
      ),
      home: Consumer(builder: (context, ref, _) {
        capturedRef = ref;
        return AndroidHomePage(pairing: pairing);
      }),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 主机（Windows 本地截屏）广播 task_update：不需要用户下拉。
    final sink = RefLiveUpdateSink(capturedRef);
    sink.taskUpdate(
      taskId: 't1',
      status: TaskState.analyzing,
      sessionId: 's1',
      imageCount: 2,
    );
    await tester.pump();
    expect(find.text('2 张图片识别中…'), findsOneWidget);

    // task_result 落库后当前任务页直接显示答案。
    await app.repo.upsertSession(Session(
      sessionId: 's1',
      collectionId: 'c1',
      imageHash: 'h1',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await app.repo.upsertQuestion(Question(
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      stem: '题目',
      type: QuestionType.blank,
      answerText: '答案',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    sink.taskResult(sessionId: 's1', questionCount: 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('task-done')), findsOneWidget);
    expect(find.text('答案'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('识别模块关闭时不显示悬浮球（setBallVisible(false)）', (tester) async {
    await pumpHome(tester, info: pairing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(channelLog.contains('setBallVisible'), isTrue,
        reason: '关着时必须主动把悬浮球隐藏');
    await unmount(tester);
  });

  testWidgets('已连接电脑但未开始任务：只说明怎么开始，不再重复连接状态（需求 D1）',
      (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    await pumpHome(
        tester,
        info: pairing,
        gateway: FakeHostGateway(
          activeCollectionId: 'c1',
          activeCollectionName: '期末复习',
          availableCollections: [sampleCollection()],
        ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('还没开始识别'), findsOneWidget);
    // 连接状态只由页面最上方的 host-status 卡片说一次，下面不再重复。
    expect(find.text('已连接电脑，但未开始任务'), findsNothing);
    expect(find.byKey(const ValueKey('host-status-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-from-gallery')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('主机未选合集：状态行提示「电脑还没选合集」且上传入口不可用',
      (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    await pumpHome(tester, info: pairing, gateway: FakeHostGateway());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已连接 · 电脑还没选合集'), findsOneWidget);
    expect(find.text('还没开始识别'), findsNothing);
    expect(find.byKey(const ValueKey('pick-from-gallery')), findsNothing,
        reason: '主机没选合集时不允许发起识别（需求 12）');
    // 手机上仍可替主机挑一个合集（需求 12）。
    expect(find.byKey(const ValueKey('pick-collection')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('主机离线：显示「电脑未连接」并可重试', (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    final gateway = FakeHostGateway(
        infoError: const ApiClientException(0, 'network_error', '无法连接主机'));
    await pumpHome(tester, info: pairing, gateway: gateway);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('电脑未连接'), findsWidgets);
    final before = gateway.infoCalls;
    await tester.tap(find.byKey(const ValueKey('refresh-host')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(gateway.infoCalls, greaterThan(before), reason: '重试要真的再探一次');
    await unmount(tester);
  });

  testWidgets('历史记录按合集分组：合集 + 未分类，点进未分类看记录', (tester) async {
    await app.repo.upsertCollection(sampleCollection());
    await addSession(app, 's1', stem: '合集中的题', collectionId: 'c1');
    await addSession(app, 's2', stem: '没归类的题');

    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('期末复习'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('1 条识别记录'), findsNWidgets(2));

    // 点进「未分类」：只看到没归属合集的记录。
    await tester.tap(find.byKey(const ValueKey('group-unclassified')));
    await tester.pumpAndSettle();
    expect(find.text('识别出 1 道题'), findsOneWidget);
    // 需求 A：安卓端不再有导出/分享入口（导出在 Windows 端做）。
    expect(find.byKey(const ValueKey('export-this-collection')), findsNothing);
    expect(find.byKey(const ValueKey('export-collection')), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    await unmount(tester);
  });

  testWidgets('M18 第 2 条：长按选中合集 → 批量删除（二次确认）', (tester) async {
    await app.repo.upsertCollection(sampleCollection());
    await app.repo.upsertCollection(Collection(
      collectionId: 'c2',
      name: '第二合集',
      createdAt: 2,
      updatedAt: 2,
      updatedBy: 'android-local',
    ));
    await addSession(app, 's1', stem: '合集中的题', collectionId: 'c1');
    await addSession(app, 's2', stem: '没归类的题');

    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('期末复习'), findsOneWidget);
    expect(find.byKey(const ValueKey('collection-selection-count')), findsNothing,
        reason: '没长按之前不能有多选操作栏');

    // 长按 = 选中这个合集并进入多选模式（用户要求「可以选中删除合集」）。
    await tester.longPress(find.byKey(const ValueKey('group-c1')));
    await tester.pump();
    expect(find.text('已选 1 个合集'), findsOneWidget);

    // 多选模式下单击 = 切换选中（不再进合集详情）。
    await tester.tap(find.byKey(const ValueKey('group-c2')));
    await tester.pump();
    expect(find.text('已选 2 个合集'), findsOneWidget);

    // 「未分类」不是合集：选中它也点不动（不能删记录视图）。
    await tester.tap(find.byKey(const ValueKey('group-unclassified')));
    await tester.pump();
    expect(find.text('已选 2 个合集'), findsOneWidget,
        reason: '「未分类」没有可删的合集');

    await tester.tap(find.byKey(const ValueKey('collection-select-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删除选中的 2 个合集？'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-delete-cancel')));
    await tester.pumpAndSettle();
    expect(await app.repo.getCollection('c1'), isNotNull, reason: '取消不能删');

    await tester.tap(find.byKey(const ValueKey('collection-select-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collection-delete-confirm')));
    await tester.pumpAndSettle();

    expect(await app.repo.getCollection('c1'), isNull);
    expect(await app.repo.getCollection('c2'), isNull);
    expect(find.byKey(const ValueKey('collection-selection-count')), findsNothing,
        reason: '删完退出多选模式');
    // 合集不级联删记录：那条记录回到「未分类」。
    expect(await app.repo.getSession('s1'), isNotNull);
    expect(find.text('未分类'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('历史搜索无结果：提示「没有匹配的记录」并可一键清空', (tester) async {
    await addSession(app, 's1', stem: '测试题干');
    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(find.byKey(const ValueKey('search-box')), 'zzzzz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 等防抖

    expect(find.text('没有匹配的记录'), findsOneWidget);
    expect(find.text('还没有识别记录'), findsNothing);

    await tester.tap(find.text('清空搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未分类'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('删除记录要二次确认：取消不删，确认才删', (tester) async {
    await addSession(app, 's1', stem: '待删除的题');
    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('group-unclassified')));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('识别出 1 道题'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条识别记录？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await app.repo.getSession('s1'), isNotNull, reason: '取消不能删');

    await tester.longPress(find.text('识别出 1 道题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await app.repo.getSession('s1'), isNull, reason: '确认后软删除');
    await unmount(tester);
  });

  testWidgets('设置页：识别模块开关 + 主题三态，且不再有配色选择', (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('recognition-switch')), findsOneWidget);
    // M19 第 3 条：识别模块开关下面必须写清「可能识别时间过长，不建议开启」。
    expect(find.byKey(const ValueKey('recognition-slow-note')), findsOneWidget,
        reason: '识别模块是绕一圈的路径，开关旁要有耗时说明');
    expect(find.text(kRecognitionSlowNote), findsOneWidget,
        reason: '文案必须与 kRecognitionSlowNote 完全一致');
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    // 需求 10：配色（accent）选择已从安卓设置页移除。
    expect(find.byType(AccentPicker), findsNothing);
    expect(find.byKey(const ValueKey('open-recognition-settings')),
        findsOneWidget);

    // M18 第 1 条：关于页的版本行只有 v1.0.0（用户原话「关于不要写构建 8，
    // 这就是 1.0.0 正式版，前面全是预览版」）——整行文本完全相等，多一个
    // 「（构建 N）」这段断言就会红。
    // 注意滚动锚点要用「项目地址」那行：`kAppName` 在 AppBar 上也有，
    // 拿它当锚点会「立即已可见」而根本不滚。
    await tester.scrollUntilVisible(find.text('项目地址（$kAppNameEn）'), 200,
        maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(
        find.text('局域网搜题工具 · v$kAppVersion\n答案由 AI 生成，仅供参考'),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('识别模块设置二级页：截屏方式 / 悬浮球 / 多页 / 权限',
      (tester) async {
    await app.settings.updateApp(
        app.settings.app.copyWith(androidRecognitionEnabled: true));
    await pumpHome(tester, info: pairing);
    await tester.tap(find.byKey(const ValueKey('tab-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('open-recognition-settings')));
    await tester.pumpAndSettle();

    expect(find.text('截屏方式'), findsOneWidget);
    // M19 第 3 条：二级页顶部同样挂着这条说明（两处入口共用同一组件）。
    expect(find.text(kRecognitionSlowNote), findsOneWidget);
    expect(find.text('一题多页'), findsOneWidget);
    // 用户需求 5：一题多页写清操作顺序（长按截取第 1 张 → 松手 → 再长按第 2 张 → 短按收尾）。
    final help =
        tester.widget<Text>(find.byKey(const ValueKey('multipage-help')));
    final helpText = help.data!;
    expect(helpText, contains('「长按」悬浮球截取第 1 张'));
    expect(helpText, contains('松手即完成一页'));
    expect(helpText, contains('最多 ${app.settings.app.multiPageLimit} 张'));
    expect(helpText, contains('最后「短按」悬浮球收尾'));
    expect(helpText.indexOf('第 1 张'), lessThan(helpText.indexOf('第 2 张')));
    expect(helpText.indexOf('第 2 张'),
        lessThan(helpText.indexOf('最后「短按」悬浮球收尾')));
    // 用户需求 6：不再点名任何系统 / 品牌。
    for (final brand in ['MIUI', 'ColorOS', 'EMUI', 'HyperOS', '小米', '华为']) {
      expect(find.textContaining(brand), findsNothing, reason: brand);
    }
    expect(find.textContaining('国产'), findsNothing);
    // 权限设置是最后一块，先滚到可见（ListView 懒构建）。
    await tester.scrollUntilVisible(find.text('权限设置'), 200,
        maxScrolls: 30);
    await tester.pumpAndSettle();
    expect(find.text('权限设置'), findsOneWidget);
    // M14 第 7 条：安卓端不再提供「图片缓存上限」选项（固定只留最近 20 张）。
    expect(find.text('图片缓存'), findsNothing);
    expect(find.text('不设限'), findsNothing);
    expect(find.byKey(const ValueKey('cache-limit-0')), findsNothing);
    await unmount(tester);
  });

  testWidgets('重新配对成功：收起配对页并切回「当前任务」标签（M14 第 5 条）', (tester) async {
    await pumpHome(tester,
        info: pairing, pairingClient: (_) => FakePairingClient());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AndroidHomePage)),
        listen: false);
    // 用户是从「设置」标签里发起重新配对的，这里还原那一刻的现场。
    container.read(tabIndexProvider.notifier).state = 2;
    await tester.pump();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);

    await tester.tap(find.byKey(const ValueKey('repair')));
    await tester.pumpAndSettle();

    // 扫码 / 粘贴链接 / 手动输入三条路都汇合到 `_pair`，这里走手动输入。
    await tester.enterText(
        find.widgetWithText(TextField, '主机地址（如 192.168.1.23）'),
        '127.0.0.1');
    await tester.enterText(
        find.widgetWithText(TextField, '6 位配对码'), '123456');
    // 配对页是可滚动的列表，按钮在首屏之下。
    await tester.ensureVisible(find.text('开始配对'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始配对'));
    await tester.pumpAndSettle();

    expect(container.read(tabIndexProvider), 0,
        reason: '配对成功后当前标签必须是 0（当前任务）');
    expect((await app.loadPairing())?.token, 'new-token',
        reason: '确实走的是配对成功分支，不是失败分支');
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
    expect(find.text('方式三：手动输入'), findsNothing,
        reason: '配对页要收起来，用户才真的回到主界面');
    await unmount(tester);
  });
}
