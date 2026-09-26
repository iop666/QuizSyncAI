import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/state/providers.dart';
import 'package:quizsync_android/ui/current_task_page.dart';
import 'package:quizsync_android/ui/result_page.dart';

import 'support.dart';

/// 结果页（用户需求 1/3/7）：
/// 一次识别的所有题目同页显示；「上一次识别 / 下一次识别」在**会话之间**跳转；
/// 标题是「第 N/M 次识别」；有「重新生成」。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;

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
  });

  tearDown(() async => db.close());

  testWidgets('两次识别：「上一次识别 / 下一次识别」在会话之间跳转', (tester) async {
    // s1 更早，s2 更新（列表按时间倒序）。
    await addSession(app, 's1', stem: '第一题', createdAt: 1000);
    await addSession(app, 's2', stem: '第二题', createdAt: 2000);

    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      home: const ResultPage(sessionId: 's2'),
    ));
    await tester.pumpAndSettle();

    // 打开的是最新一条 → 第 1 / 2 次识别。
    expect(find.textContaining('第 1 / 2 次识别'), findsOneWidget);
    expect(find.text('上一次识别'), findsOneWidget);
    expect(find.text('下一次识别'), findsOneWidget);

    // 打开最新一条时「下一次」没有更晚的会话 → 禁用。
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('next-session')))
          .onPressed,
      isNull,
    );

    // 点「上一次识别」→ 跳到更早的那次（第 2 / 2 次识别）。
    await tester.tap(find.byKey(const ValueKey('prev-session')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 次识别'), findsOneWidget);
    expect(find.text('第一题'), findsOneWidget);
    // 现在轮到自己有更晚的会话 → 「下一次识别」可用。
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('next-session')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('next-session')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 2 次识别'), findsOneWidget);
    expect(find.text('第二题'), findsOneWidget);
  });

  testWidgets('同一次识别的多道题在同一页纵向显示（不再会话内分页）', (tester) async {
    await app.repo.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'android-local',
      status: TaskState.done,
      questionCount: 2,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'android-local',
    ));
    for (var i = 0; i < 2; i++) {
      await app.repo.upsertQuestion(Question(
        questionId: 'q$i',
        sessionId: 's1',
        ordinal: i,
        questionNo: '${i + 3}',
        stem: '第 $i 道题的题干',
        type: QuestionType.blank,
        answerText: '答案 $i',
        createdAt: 1000,
        updatedAt: 1000,
        updatedBy: 'android-local',
      ));
    }
    await app.repo.setSessionImages('s1', ['h1', 'h2']);

    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      home: const ResultPage(sessionId: 's1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('第 0 道题的题干'), findsOneWidget);
    expect(find.text('第 1 道题的题干'), findsOneWidget);
    expect(find.text('共 2 题'), findsOneWidget);
    expect(find.text('2 张图片'), findsOneWidget);
  });

  testWidgets('重新生成按钮：点击调用主机 reanalyze，未选合集时给同一句文案',
      (tester) async {
    await addSession(app, 's1', stem: '题干', createdAt: 1000);
    final gateway = FakeHostGateway();
    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      gateway: gateway,
      home: const ResultPage(sessionId: 's1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reanalyze')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reanalyze')));
    await tester.pumpAndSettle();
    expect(gateway.reanalyzeCalls, 1);
    expect(gateway.reanalyzeSessionId, 's1');

    // 等第一个 SnackBar 自己消失，否则第二个会排队、断言看不到。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 409 no_active_collection 要按需求 12 的文案提示，而不是原始错误。
    gateway.reanalyzeError =
        const ApiClientException(409, 'no_active_collection', '先选合集');
    await tester.tap(find.byKey(const ValueKey('reanalyze')));
    await tester.pumpAndSettle();
    expect(find.text('请先在电脑上选择任务合集'), findsOneWidget);
  });

  testWidgets('识别中 / 无结果时显示失败或空状态而不是崩溃', (tester) async {
    await app.repo.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'android-local',
      status: TaskState.failed,
      errorCode: 'ai_timeout',
      questionCount: 0,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'android-local',
    ));
    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      home: const ResultPage(sessionId: 's1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('分析失败'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
  });

  // ------------------------------------------------------------------
  // M16 第 3 条：停在结果页时，电脑开始识别也要看得见
  // ------------------------------------------------------------------

  /// 结果页上的任务状态通知器（真实入口是 WS / 1 秒轮询，两个都汇到这里）。
  ActiveTaskNotifier taskOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(ResultPage)),
      ).read(activeTaskProvider.notifier);

  Future<void> pumpResult(WidgetTester tester) async {
    await addSession(app, 's1', stem: '上一轮的题', createdAt: 1000);
    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      home: const ResultPage(sessionId: 's1'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('电脑开始识别：结果页上方浮起「电脑正在识别中」，原结果不消失', (tester) async {
    await pumpResult(tester);
    expect(find.byKey(const ValueKey('result-next-banner')), findsNothing);

    // 主机（Windows）自己截屏识别：task_update analyzing。
    taskOf(tester).update(
      taskId: 't-win',
      status: TaskState.analyzing,
      sessionId: 's-win',
      imageCount: 3,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('result-next-banner')), findsOneWidget);
    expect(find.text('电脑正在识别中…（3 张图片）'), findsOneWidget);
    // 用户需求 3：上一轮结果仍然留在页面上（不擦掉）。
    expect(find.text('上一轮的题'), findsOneWidget);
  });

  testWidgets('M18 第 3 条：浮层画在最上层，底色不透明度 85%', (tester) async {
    await pumpResult(tester);
    taskOf(tester).update(
      taskId: 't-win',
      status: TaskState.analyzing,
      sessionId: 's-win',
      imageCount: 2,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final banner = find.byKey(const ValueKey('result-next-banner'));
    expect(banner, findsOneWidget);

    // ① 必须画在内容的**上面**。Stack 里后画的在上面，所以它得是最后一个孩子：
    //    原实现把它放在第一个孩子 → 被题目盖住（用户原话「渲染在识别结果题目下」）。
    final stack = tester.widget<Stack>(
        find.ancestor(of: banner, matching: find.byType(Stack)).first);
    expect(stack.children, hasLength(2), reason: '内容 + 浮层');
    expect(stack.children.first, isA<Positioned>(), reason: '内容先画（被压住）');
    final top = stack.children.last;
    expect(top, isA<Positioned>());
    expect((top as Positioned).child.key,
        const ValueKey('result-next-banner'),
        reason: '浮层必须是最后一个孩子，才画在题目上面');

    // ② 底色 85% 不透明（文字与图标仍完全不透明，压在题目上也读得清）。
    final card = tester.widget<Card>(find
        .descendant(of: banner, matching: find.byType(Card))
        .first);
    expect(card.color!.a, closeTo(0.85, 0.001));
  });

  testWidgets('本机（悬浮球 / 相册）识别：结果页保持静默，没有悬浮窗', (tester) async {
    await pumpResult(tester);
    taskOf(tester).begin(imageCount: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('result-next-banner')), findsNothing,
        reason: '用户需求 3：本机识别全程静默');

    // 主机会把同一条状态**广播回来**：仍然不能当成「电脑在识别」。
    taskOf(tester).update(
      taskId: 't-phone',
      status: TaskState.analyzing,
      sessionId: 's-phone',
      imageCount: 2,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('result-next-banner')), findsNothing,
        reason: '本机任务的回声不能触发悬浮窗');
  });

  testWidgets('电脑识别完成：悬浮窗变成「识别完成，正在打开新结果…」', (tester) async {
    await pumpResult(tester);
    taskOf(tester).update(
      taskId: 't-win',
      status: TaskState.analyzing,
      sessionId: 's-win',
      imageCount: 1,
    );
    await tester.pump();
    taskOf(tester).done(sessionId: 's-win', autoOpen: true);
    await tester.pump();

    expect(find.text('识别完成，正在打开新结果…'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-next-banner')), findsOneWidget);
  });

  testWidgets('正在看的那次自己重新生成：不弹「电脑正在识别」悬浮窗', (tester) async {
    await pumpResult(tester);
    // 主机重跑**当前这次**（session_id 就是页面上的这次）。
    taskOf(tester).update(
      taskId: 't-re',
      status: TaskState.analyzing,
      sessionId: 's1',
      imageCount: 1,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('result-next-banner')), findsNothing);
  });

  testWidgets('真实结构（当前任务页在下面 + 结果页在上面）：完成后新结果页被推上来',
      (tester) async {
    await addSession(app, 's1', stem: '上一轮的题', createdAt: 1000);
    // 复刻真机：抽屉里「当前任务」页一直在（IndexedStack），结果页是推上去的。
    await tester.pumpWidget(wrapApp(
      app,
      pairing: pairing,
      home: const Scaffold(body: CurrentTaskPage()),
    ));
    await tester.pump();
    Navigator.of(tester.element(find.byType(CurrentTaskPage))).push(
      MaterialPageRoute(builder: (_) => const ResultPage(sessionId: 's1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('上一轮的题'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ResultPage)),
    );
    final notifier = container.read(activeTaskProvider.notifier);
    notifier.update(
      taskId: 't-win',
      status: TaskState.analyzing,
      sessionId: 's-new',
      imageCount: 2,
    );
    await tester.pump();
    expect(find.text('电脑正在识别中…（2 张图片）'), findsOneWidget,
        reason: '结果页浮层与「当前任务」页的悬浮窗是同一份语义');

    await addSession(app, 's-new', stem: '新一轮的题', createdAt: 2000);
    notifier.done(sessionId: 's-new', autoOpen: true);
    await tester.pump();
    expect(find.text('识别完成，正在打开新结果…'), findsOneWidget);

    // 「当前任务」页 400ms 后把新结果页推上来（单一出口，不会推两个）。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('新一轮的题'), findsOneWidget);
    expect(find.textContaining('第 1 / 2 次识别'), findsOneWidget);
    expect(find.text('识别完成，正在打开新结果…'), findsNothing,
        reason: '跳过去之后悬浮窗要消失（标记只消费一次）');
    expect(find.byType(ResultPage), findsOneWidget);
  });
}
