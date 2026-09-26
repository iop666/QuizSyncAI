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

/// 「当前任务」页 + 主机识别的状态机（用户需求 3）：
///
/// - 主机开始识别 → 显示「N 张图片识别中…」，**上一次的结果不消失**，
///   改成在上方加一条悬浮窗；
/// - 主机出结果 → 自动进入本次结果页（只跳一次、后台不抢前台）；
/// - 本机识别 → 静默：不切标签、不跳页。
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
    installCaptureChannelMock();
  });

  tearDown(() async {
    clearCaptureChannelMock();
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester, {PairingInfo? info}) async {
    await tester.pumpWidget(wrapApp(
      app,
      gateway: FakeHostGateway(
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
      ),
      pairing: info,
      home: const Scaffold(body: CurrentTaskPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(CurrentTaskPage)));

  /// 上一轮的识别结果（已经在页面上显示）。
  Future<void> addPreviousResult() async {
    await app.repo.upsertSession(Session(
      sessionId: 's-prev',
      collectionId: 'c1',
      imageHash: 'h-prev',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await app.repo.upsertQuestion(Question(
      questionId: 'q-prev',
      sessionId: 's-prev',
      ordinal: 0,
      stem: '上一轮的题',
      type: QuestionType.single,
      choice: const ['A'],
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
  }

  testWidgets('task_update(analyzing)：显示 N 页识别中，且上一轮结果仍然可见',
      (tester) async {
    await addPreviousResult();
    await pumpPage(tester, info: pairing);
    final container = containerOf(tester);

    // 上一轮：完成并显示在当前任务页。
    container.read(activeTaskProvider.notifier).done(sessionId: 's-prev');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // 等本地库读题目
    expect(find.byKey(const ValueKey('task-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-answer-q-prev')), findsOneWidget);

    // 主机开始下一轮（Windows 按下热键 → task_update analyzing）。
    container.read(activeTaskProvider.notifier).update(
          taskId: 't-next',
          status: TaskState.analyzing,
          sessionId: 's-next',
          imageCount: 3,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 上方悬浮窗显示进度，下面仍然是上一轮的结果。
    expect(find.byKey(const ValueKey('next-task-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-task-banner-text')), findsOneWidget);
    expect(find.text('3 张图片识别中…'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-done')), findsOneWidget,
        reason: '新一轮识别不能擦掉上一轮已经显示的结果');
    expect(find.byKey(const ValueKey('task-answer-q-prev')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-running')), findsNothing,
        reason: '有旧结果时用悬浮窗，而不是整块「识别中」卡片');
    // 这一轮还在跑：旧结果卡片不能有「忽略」（清空会把上面的进度一起擦掉），
    // 但仍然可以点进去看上一轮的完整结果。
    expect(find.text('忽略'), findsNothing);
    expect(find.byKey(const ValueKey('open-result')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('第一次识别（没有旧结果）：仍然用原来的「识别中」卡片', (tester) async {
    await pumpPage(tester, info: pairing);
    final container = containerOf(tester);

    container.read(activeTaskProvider.notifier).update(
          taskId: 't1',
          status: TaskState.analyzing,
          sessionId: 's1',
          imageCount: 2,
        );
    await tester.pump();

    expect(find.byKey(const ValueKey('task-running')), findsOneWidget);
    expect(find.text('2 张图片识别中…'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-task-banner')), findsNothing);
    await unmount(tester);
  });

  testWidgets('task_result（主机发起）：自动进入结果页，且待跳标记只消费一次',
      (tester) async {
    await addPreviousResult();
    await pumpPage(tester, info: pairing);
    final container = containerOf(tester);
    final notifier = container.read(activeTaskProvider.notifier);

    notifier.done(sessionId: 's-prev');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.update(
      taskId: 't-next',
      status: TaskState.analyzing,
      sessionId: 's-next',
      imageCount: 1,
    );
    await tester.pump();

    // 新一轮结果落库（主机的 task_result 会先把会话写进本地库）。
    await app.repo.upsertSession(Session(
      sessionId: 's-next',
      collectionId: 'c1',
      imageHash: 'h-next',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await app.repo.upsertQuestion(Question(
      questionId: 'q-next',
      sessionId: 's-next',
      ordinal: 0,
      stem: '新一轮的题',
      type: QuestionType.blank,
      answerText: '新答案',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));

    // 主机发起的识别：done(autoOpen: true)。
    notifier.done(sessionId: 's-next', autoOpen: true);
    await tester.pump();

    // 跳之前先露一下「识别完成」的悬浮窗（用户需求 3）。
    expect(find.byKey(const ValueKey('next-task-banner')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('next-task-banner-text')))
            .data,
        '识别完成');
    expect(find.byType(ResultPage), findsNothing, reason: '不应该在 build 期间跳页');

    await tester.pump(CurrentTaskPage.autoOpenDelay);
    await tester.pump(const Duration(milliseconds: 400)); // 等路由动画
    expect(find.byType(ResultPage), findsOneWidget, reason: '完成后自动进入结果页');
    expect(container.read(activeTaskProvider).autoOpenResult, isFalse,
        reason: '待跳标记必须被消费掉，不能再跳第二次');
    expect(find.byType(ResultPage), findsOneWidget);
    await unmount(tester);
  });

  test('只有「主机完成 + 前台」才自动进结果页（后台不抢前台）', () {
    // 纯函数先行：paused / hidden / detached 都不跳。
    const task = ActiveTask(
        started: true,
        status: TaskState.done,
        sessionId: 's1',
        autoOpenResult: true);
    expect(shouldAutoOpenResult(task, AppLifecycleState.paused), isFalse);
    expect(shouldAutoOpenResult(task, AppLifecycleState.hidden), isFalse);
    expect(shouldAutoOpenResult(task, AppLifecycleState.detached), isFalse);
    expect(shouldAutoOpenResult(task, AppLifecycleState.resumed), isTrue);
    expect(shouldAutoOpenResult(task, AppLifecycleState.inactive), isTrue);
    expect(shouldAutoOpenResult(task, null), isTrue,
        reason: '还没收到生命周期事件时按前台处理（首帧）');
    expect(
        shouldAutoOpenResult(
            const ActiveTask(started: true, status: TaskState.done), null),
        isFalse,
        reason: '没有待跳标记就不跳');
  });

  testWidgets('本机识别：既不改标签也不跳页（用户需求 3 的静默）', (tester) async {
    await pumpPage(tester, info: pairing);
    final container = containerOf(tester);

    // 用户先切到「设置」标签，然后在别的页面触发本机识别。
    container.read(tabIndexProvider.notifier).state = 2;
    await tester.pump();

    container.read(activeTaskProvider.notifier).begin(imageCount: 1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(tabIndexProvider), 2, reason: '本机识别不能把用户拽回当前任务页');
    expect(find.byType(ResultPage), findsNothing, reason: '本机识别不自动跳结果页');
    expect(container.read(activeTaskProvider).autoOpenResult, isFalse);
    await unmount(tester);
  });
}
