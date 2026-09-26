import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/services/host_status_poller.dart';
import 'package:quizsync_android/services/live_updates.dart';
import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/state/providers.dart';
import 'package:quizsync_android/ui/current_task_page.dart';
import 'package:quizsync_android/ui/home_page.dart';
import 'package:quizsync_android/ui/result_page.dart';

import 'support.dart';

/// M15 第 4 条（用户反馈）：「windows 识别时安卓端当前任务还是不直接刷新，
/// 又没有方法让他一直刷新，比如安卓端 1s 获取一次状态」。
///
/// M14 的 WS 补齐在用户那台机器上没能解决问题（最可能是 WS 推送根本连不上，
/// 而 HTTP 一直可用），所以这一轮加轮询兜底。这里钉住四件事：
/// 1. 按间隔探测、`stop()` 之后不再探测、上一次没回来时**不重入**；
/// 2. 一条 `analyzing → done` 的轮询序列能驱动「当前任务」页（复用 WS 的
///    同一套 `LiveUpdates` / `LiveUpdateSink` 语义），完成时自动进结果页；
/// 3. 状态没变时**一条通知都不发**（每秒 invalidate 整个列表会抖）；
/// 4. 失败静默降级：只改状态行，不弹 SnackBar。
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

  // ------------------------------------------------------------
  // 假探测数据（与 `GET /api/v1/tasks/active` 的响应同构）
  // ------------------------------------------------------------

  ActiveTaskView idleView() => const ActiveTaskView(
        status: 'idle',
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
      );

  ActiveTaskView analyzingView({int imageCount = 2}) => ActiveTaskView(
        status: 'analyzing',
        taskId: 't-1',
        sessionId: 's-1',
        imageCount: imageCount,
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
        updatedAt: 1000,
      );

  ActiveTaskView doneView({
    String sourceDevice = 'server-1',
    int updatedAt = 2000,
  }) =>
      ActiveTaskView(
        status: 'done',
        taskId: 't-1',
        sessionId: 's-1',
        imageCount: 2,
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
        updatedAt: updatedAt,
        session: {
          'session_id': 's-1',
          'collection_id': 'c1',
          'image_hash': 'h-1',
          'source_device': sourceDevice,
          'status': 'done',
          'question_count': 1,
          'created_at': 1000,
          'updated_at': updatedAt,
          'updated_by': sourceDevice,
          'image_hashes': ['h-1', 'h-2'],
          'questions': [
            {
              'question_id': 'q-1',
              'session_id': 's-1',
              'ordinal': 0,
              'question_no': '12',
              'stem': '主机识别出来的题干',
              'type': 'single',
              'choice': ['B'],
              'created_at': 1000,
              'updated_at': updatedAt,
              'updated_by': sourceDevice,
            }
          ],
        },
      );

  /// 只记事件名的假宿主：断言「有没有通知、通知了几次」用。
  final sink = _RecordingSink();
  late LiveUpdates updates;
  setUp(() {
    sink.reset();
    updates = LiveUpdates(app: app, sink: sink);
  });

  // ------------------------------------------------------------
  // 1. 生命周期
  // ------------------------------------------------------------

  testWidgets('按间隔探测；stop() 之后不再探测', (tester) async {
    var calls = 0;
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async {
        calls++;
        return idleView();
      },
      interval: kHostStatusPollInterval,
    );

    poller.start(pairing);
    expect(calls, 1, reason: 'start 后立刻问一次：用户按下热键随手开 App 时不必等满 1s');

    await tester.pump(kHostStatusPollInterval);
    expect(calls, 2);
    await tester.pump(kHostStatusPollInterval);
    expect(calls, 3, reason: '默认间隔就是用户要求的 1 秒');

    poller.stop();
    await tester.pump(kHostStatusPollInterval * 3);
    expect(calls, 3, reason: 'stop() 之后一次都不能再问（dispose / 取消配对 / 进后台）');
  });

  testWidgets('上一次没回来就跳过这一轮（不允许重入）', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async {
        calls++;
        // 第一次探测故意挂着不返回（连接超时是 5s、间隔是 1s）。
        if (calls == 1) await gate.future;
        return idleView();
      },
      interval: kHostStatusPollInterval,
    );

    poller.start(pairing);
    expect(calls, 1);
    await tester.pump(kHostStatusPollInterval * 3);
    expect(calls, 1,
        reason: '上一次没回来就不能再叠加请求，否则不可达的主机会攒一堆并发连接');

    gate.complete();
    await tester.pump();
    await tester.pump(kHostStatusPollInterval);
    expect(calls, 2, reason: '上一次回来之后恢复原来的节奏');
    poller.stop();
  });

  // ------------------------------------------------------------
  // 2. 与 WS 完全相同的语义
  // ------------------------------------------------------------

  testWidgets('轮询序列 analyzing → done：先显示识别中，再自动进结果页', (tester) async {
    // 每次探测返回**新的对象、同样的字段**：模拟真实 HTTP 响应，
    // 用来验证「按内容而不是按对象身份」判断状态有没有变。
    var analyzing = true;
    var invalidations = 0;

    await tester.pumpWidget(wrapApp(
      app,
      hostPolling: true,
      probe: (_) => () async =>
          analyzing ? analyzingView(imageCount: 3) : doneView(),
      pairing: pairing,
      gateway: FakeHostGateway(
        activeCollectionId: 'c1',
        activeCollectionName: '期末复习',
      ),
      home: AndroidHomePage(pairing: pairing),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('3 张图片识别中…'), findsOneWidget,
        reason: '一条推送都没收到，轮询也要让「当前任务」页显示进度');
    expect(find.byKey(const ValueKey('task-running')), findsOneWidget);

    // 计数用的订阅：状态没变时这个数不能再涨（否则每秒重建整棵列表）。
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AndroidHomePage)),
        listen: false);
    final sub = container.listen(sessionsProvider(null), (_, _) {
      invalidations++;
    });
    addTearDown(sub.close);
    await tester.pump();
    final settled = invalidations;
    // 状态没变的 5 秒。
    await tester.pump(kHostStatusPollInterval * 5);
    expect(invalidations, settled,
        reason: '状态没变就不能反复 invalidate：每秒重建整个列表会抖');
    // 自检：这个计数确实能反映 invalidate，否则上面那条断言等于没写。
    container.invalidate(sessionsProvider(null));
    await tester.pump();
    expect(invalidations, greaterThan(settled));

    // 主机出结果（依然没有任何 WS 推送）。
    analyzing = false;
    await tester.pump(kHostStatusPollInterval);
    await tester.pump();

    await tester.pump(CurrentTaskPage.autoOpenDelay);
    await tester.pump(const Duration(milliseconds: 400)); // 等路由动画
    expect(find.byType(ResultPage), findsOneWidget,
        reason: '主机发起的识别完成后要自动进入本次结果页（与 WS 同一语义）');
    expect(container.read(activeTaskProvider).autoOpenResult, isFalse,
        reason: '待跳标记必须被消费掉，不能再跳第二次');

    // 结果来自轮询：会话与题目都要落进本地库（历史里能离线看）。
    final session = await app.repo.getSession('s-1');
    expect(session, isNotNull);
    expect(session!.sourceDevice, 'server-1');
    expect((await app.repo.questionsOfSession('s-1')).single.stem, '主机识别出来的题干');

    // 稳定之后继续轮询：不能因为「同一个会话的 done」又把结果页推一次。
    await tester.pump(kHostStatusPollInterval * 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ResultPage), findsOneWidget,
        reason: 'WS 与轮询并存时最容易踩的重复跳页');

    // 让轮询停掉（dispose）。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('轮询到底：一条通知都不多的静默路径（用假宿主计数）', (tester) async {
    var view = analyzingView();
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.events.where((e) => e == 'task_update'), hasLength(1));

    // 状态没变：连着问 5 次，一条通知都不该再多出来。
    for (var i = 0; i < 5; i++) {
      await poller.pollOnce();
      await tester.pump();
    }
    expect(sink.taskUpdates, hasLength(1), reason: '状态没变不能重复通知');
    expect(sink.events.where((e) => e == 'collection'), hasLength(1),
        reason: '合集没变也不能反复刷状态行');

    // 页数变了：算「状态变了」，要通知（「N 张图片识别中」得跟着更新）。
    view = analyzingView(imageCount: 4);
    await poller.pollOnce();
    await tester.pump();
    expect(sink.taskUpdates, hasLength(2));
    expect(sink.taskUpdates.last['image_count'], 4);
    poller.stop();
  });

  testWidgets('本机自己发起的识别：轮询不会把它当成主机发起（不跳结果页）',
      (tester) async {
    // 手机相册上传的会话，source_device 就是本机。
    var view = analyzingView();
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
    );
    poller.start(pairing);
    await tester.pump();

    // 主机把这份结果也报回来了：与 WS 的 task_result 一样要认出是自己发起的。
    view = doneView(sourceDevice: 'android-local');
    await poller.pollOnce();
    await tester.pump();

    expect(sink.resultSessionId, 's-1');
    expect(sink.resultSelfInitiated, isTrue,
        reason: '与 live_updates.dart 里 selfInitiated 的判断保持一致（看 sourceDevice）');
    poller.stop();
  });

  testWidgets('冷启动时主机报的「上一轮已完成」只当基线：不会自动跳旧结果页',
      (tester) async {
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => doneView(),
      interval: kHostStatusPollInterval,
    );
    poller.start(pairing);
    await tester.pump();

    expect(sink.events, isNot(contains('task_result')),
        reason: '第一次观测就是终态 = 主机早就结束了，只记基线（WS 也只补发进行中的）');
    expect(await app.repo.getSession('s-1'), isNull);
    poller.stop();
  });

  // ------------------------------------------------------------
  // 3. 失败静默降级
  // ------------------------------------------------------------

  testWidgets('探测失败：只把状态行改成「电脑未连接」，不重复刷', (tester) async {
    var failing = true;
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async {
        if (failing) {
          throw const ApiClientException(0, 'network_error', '无法连接主机');
        }
        return idleView();
      },
      interval: kHostStatusPollInterval,
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.offlineCount, 1, reason: '失败只降级状态行，绝不弹 SnackBar');
    expect(poller.online, isFalse);

    // 一直失败：不能每秒再刷一次状态行。
    for (var i = 0; i < 3; i++) {
      await poller.pollOnce();
      await tester.pump();
    }
    expect(sink.offlineCount, 1);

    // 恢复：走 collection_changed 这条路把连接改回「已连接」（WS 的 hello 同理）。
    failing = false;
    await poller.pollOnce();
    await tester.pump();
    expect(poller.online, isTrue);
    expect(sink.events.last, 'collection');
    poller.stop();
  });

  testWidgets('token 被吊销：走 device_revoked 并停止轮询', (tester) async {
    var calls = 0;
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async {
        calls++;
        throw const ApiClientException(401, 'revoked', '设备已被吊销');
      },
      interval: kHostStatusPollInterval,
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.revoked, isTrue, reason: '与 WS 的 device_revoked 同一处理：必须重新配对');
    expect(poller.running, isFalse);

    await tester.pump(kHostStatusPollInterval * 3);
    expect(calls, 1, reason: '吊销之后再轮询没有意义');
  });

  // ------------------------------------------------------------
  // 4. M17 第 4 条：只要在前台就一秒一刷新，绝不能漏
  // ------------------------------------------------------------

  testWidgets('界面停在别的任务上：主机状态没变也要补发一次', (tester) async {
    var ui = 'done|s-old'; // 界面还停在上一轮的结果上
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => analyzingView(),
      interval: kHostStatusPollInterval,
      uiSignature: () => ui,
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.taskUpdates, hasLength(1));

    // 主机那边完全没变（指纹相同），但界面一直没跟上 → 必须继续补发。
    for (var i = 0; i < 3; i++) {
      await poller.pollOnce();
      await tester.pump();
    }
    expect(sink.taskUpdates, hasLength(4),
        reason: '「通知丢过一次」之后不能永远不再发（用户第二次反馈的那条）');

    // 界面跟上了：不再重复通知（否则每秒重建界面）。
    ui = HostStatusPoller.signatureOf(analyzingView());
    await poller.pollOnce();
    await tester.pump();
    expect(sink.taskUpdates, hasLength(4));

    // 用户点过「忽略 / 知道了」把界面清空 → 尊重用户，不再补发。
    ui = '';
    await poller.pollOnce();
    await tester.pump();
    expect(sink.taskUpdates, hasLength(4), reason: '用户清掉的不能被轮询又拉回来');
    poller.stop();
  });

  testWidgets('结果本地已有、但界面还没显示：仍要通知（主机同图复用会复用 session_id）',
      (tester) async {
    // 本地库里早就有这条会话（旧实现按这个条件跳过通知：`local.updatedAt >= 主机`）。
    await app.repo.upsertSession(Session(
      sessionId: 's-1',
      imageHash: 'h-1',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: 1000,
      updatedAt: 999999,
      updatedBy: 'server-1',
    ));
    var ui = 'done|s-old';
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => doneView(),
      interval: kHostStatusPollInterval,
      uiSignature: () => ui,
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.resultSessionId, 's-1',
        reason: '本地有旧记录 ≠ 界面已经看到这条结果；按本地库跳过就会「当前任务不刷新」');
    poller.stop();
  });

  testWidgets('M47：同一会话出的**新**结果也要能推到界面（闩锁按结果版本，不按 session_id）',
      (tester) async {
    // 主机「重新生成」/ 同图复用后再跑一次：session_id 不变，结果变了。
    // 老实现用裸 sessionId 做闩锁 → 第二次 done 永远被吞掉，用户只能手动下拉。
    var view = doneView(updatedAt: 2000);
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
      // 界面停在旧版本上（还没显示这一轮结果）。
      uiSignature: () => 'done|s-old',
    );

    poller.start(pairing);
    await tester.pump();
    expect(sink.events.where((e) => e == 'task_result').length, 1);

    view = doneView(updatedAt: 5000);
    await poller.pollOnce();
    await tester.pump();
    expect(sink.events.where((e) => e == 'task_result').length, 2,
        reason: '同一个 session_id 的新结果不能被闩锁吞掉');

    // 版本没变时仍然不重复推（否则每秒重建界面）。
    await poller.pollOnce();
    await tester.pump();
    expect(sink.events.where((e) => e == 'task_result').length, 2);
    poller.stop();
  });

  testWidgets('主机本地 ops 水位涨了：叫宿主只拉一次（第一次只建基线）', (tester) async {
    ActiveTaskView idleWithOps(int lamport) => ActiveTaskView(
          status: 'idle',
          activeCollectionId: 'c1',
          activeCollectionName: '期末复习',
          opsLamport: lamport,
        );
    var view = idleWithOps(5);
    var pulls = 0;
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
      onRemoteOps: () => pulls++,
    );

    poller.start(pairing);
    await tester.pump();
    expect(pulls, 0, reason: '第一次只建立基线：不能一进 App 就白拉一次');

    await poller.pollOnce();
    await tester.pump();
    expect(pulls, 0, reason: '水位没变就不拉');

    // 主机删了一个合集 → 水位涨（M17 第 5 条：Windows 没了安卓也要跟着没）。
    view = idleWithOps(9);
    await poller.pollOnce();
    await tester.pump();
    expect(pulls, 1);

    await poller.pollOnce();
    await tester.pump();
    expect(pulls, 1, reason: '同一次改动只拉一次（幂等，不刷屏）');
    poller.stop();
  });

  // ------------------------------------------------------------
  // 5. M18 第 4 条：主机活跃合集列表 → 手机本地
  // ------------------------------------------------------------

  Collection hostCollection(String id, String name, {int updatedAt = 1}) =>
      Collection(
        collectionId: id,
        name: name,
        createdAt: 1,
        updatedAt: updatedAt,
        updatedBy: 'server-1',
      );

  testWidgets('合集列表：第一次观测就镜像，变了再叫一次，不变一条都不叫',
      (tester) async {
    ActiveTaskView idleWithCollections(List<Collection> cs) =>
        ActiveTaskView(status: 'idle', collections: cs);

    var view = idleWithCollections([hostCollection('c1', '期末复习')]);
    final mirrored = <List<String>>[];
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
      onHostCollections: (list) async =>
          mirrored.add(list.map((c) => '${c.collectionId}:${c.name}').toList()),
    );

    poller.start(pairing);
    await tester.pump();
    expect(mirrored, hasLength(1),
        reason: '第一次就要镜像 —— 刻意不建基线：基线错一次就永久漏（用户报的正是这个）');

    for (var i = 0; i < 3; i++) {
      await poller.pollOnce();
      await tester.pump();
    }
    expect(mirrored, hasLength(1), reason: '列表没变就不写库（每秒重建历史列表会抖）');

    // 主机新建一个合集：下一秒就要镜像。
    view = idleWithCollections(
        [hostCollection('c1', '期末复习'), hostCollection('c2', '新合集')]);
    await poller.pollOnce();
    await tester.pump();
    expect(mirrored.last, ['c1:期末复习', 'c2:新合集']);

    // 改名也算变化（同 id、不同 name）。
    view = idleWithCollections([
      hostCollection('c1', '期末复习', updatedAt: 9),
      hostCollection('c2', '新合集'),
    ]);
    await poller.pollOnce();
    await tester.pump();
    expect(mirrored, hasLength(3), reason: '改名要让手机历史里的分组名跟着变');

    // 主机删掉 c2：列表里没了 —— 镜像回调不再被叫（只增改不删在 repo 那层保证）。
    view = idleWithCollections([hostCollection('c1', '期末复习', updatedAt: 9)]);
    await poller.pollOnce();
    await tester.pump();
    expect(mirrored, hasLength(4));
    expect(mirrored.last, ['c1:期末复习']);
    poller.stop();
  });

  testWidgets('镜像写库失败：下一轮还会重试（指纹撤回，不永久跳过）', (tester) async {
    ActiveTaskView idleWithCollections(List<Collection> cs) =>
        ActiveTaskView(status: 'idle', collections: cs);
    final view = idleWithCollections([hostCollection('c1', '期末复习')]);
    var calls = 0;
    var failing = true;
    final poller = HostStatusPoller(
      updates: updates,
      probeFactory: (_) => () async => view,
      interval: kHostStatusPollInterval,
      onHostCollections: (_) async {
        calls++;
        if (failing) throw StateError('库暂时不可写');
      },
    );

    poller.start(pairing);
    await tester.pump();
    expect(calls, 1);
    await poller.pollOnce();
    await tester.pump();
    expect(calls, 2, reason: '失败不能把指纹留在「已镜像」，否则这个合集永远进不了本地库');

    failing = false;
    await poller.pollOnce();
    await tester.pump();
    expect(calls, 3);
    await poller.pollOnce();
    await tester.pump();
    expect(calls, 3, reason: '成功之后不再重复');
    poller.stop();
  });

  testWidgets('端到端：只靠轮询，主机新建的合集出现在手机「历史」里', (tester) async {
    // 用户原话：「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」。
    // 这里不接 WS、不跑 ops 拉取，只有 1 秒一次的轮询 —— 手机也必须看得见。
    var view = ActiveTaskView(
      status: 'idle',
      activeCollectionId: 'c-host',
      activeCollectionName: '主机合集',
      collections: [hostCollection('c-host', '主机合集')],
    );
    await tester.pumpWidget(wrapApp(
      app,
      hostPolling: true,
      probe: (_) => () async => view,
      pairing: pairing,
      gateway: FakeHostGateway(
        activeCollectionId: 'c-host',
        activeCollectionName: '主机合集',
      ),
      home: AndroidHomePage(pairing: pairing),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 手机本地库真的有这一行了（主机识别的记录不会再被算进「未分类」）。
    expect((await app.repo.listCollections()).map((c) => c.collectionId),
        contains('c-host'));

    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('主机合集'), findsOneWidget,
        reason: '「windows 端的分类」要能在手机历史里看见');

    // 主机再新建一个：不用重启、不用手动下拉，1 秒一轮就会跟上。
    view = ActiveTaskView(
      status: 'idle',
      activeCollectionId: 'c-host',
      activeCollectionName: '主机合集',
      collections: [
        hostCollection('c-host', '主机合集'),
        hostCollection('c-new', '第二个合集', updatedAt: 5),
      ],
    );
    await tester.pump(kHostStatusPollInterval);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第二个合集'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}

/// 只记事件名/次数的假宿主（`live_updates_test.dart` 里那份是私有的）。
class _RecordingSink implements LiveUpdateSink {
  final List<String> events = [];
  final List<Map<String, dynamic>> taskUpdates = [];
  String? resultSessionId;
  bool resultSelfInitiated = false;
  int offlineCount = 0;
  int dataChangedCount = 0;
  bool revoked = false;

  void reset() {
    events.clear();
    taskUpdates.clear();
    resultSessionId = null;
    resultSelfInitiated = false;
    offlineCount = 0;
    dataChangedCount = 0;
    revoked = false;
  }

  @override
  void collectionChanged(String? collectionId, String? collectionName) =>
      events.add('collection');

  @override
  void serverInfo(ServerInfo info) => events.add('info');

  @override
  void taskUpdate({
    required String taskId,
    required TaskState status,
    String? sessionId,
    int imageCount = 0,
  }) {
    events.add('task_update');
    taskUpdates.add({
      'task_id': taskId,
      'status': status.wire,
      'session_id': sessionId,
      'image_count': imageCount,
    });
  }

  @override
  void taskResult({
    required String sessionId,
    required int questionCount,
    bool selfInitiated = false,
  }) {
    events.add('task_result');
    resultSessionId = sessionId;
    resultSelfInitiated = selfInitiated;
  }

  @override
  void taskFailed({required String taskId, String? message}) =>
      events.add('task_failed');

  @override
  void offline(String message) {
    events.add('offline');
    offlineCount++;
  }

  @override
  void dataChanged() {
    events.add('data_changed');
    dataChangedCount++;
  }

  @override
  void deviceRevoked() {
    events.add('revoked');
    revoked = true;
  }
}
