import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M15 第 4 条（用户反馈）：「windows 识别时安卓端当前任务还是不直接刷新，
/// 又没有方法让他一直刷新，比如安卓端 1s 获取一次状态」。
///
/// M14 已经做了「WS 断线重连补齐 + 握手时补发进行中的本机任务」，用户却仍然
/// 看不到刷新 —— 最可能是他那台机器上 WS 推送根本连不上（HTTP 一直可用）。
/// 于是加一个**只读**端点给安卓端轮询：`GET /api/v1/tasks/active`。
///
/// 这里在真服务端上钉住三件事：
/// 1. 没有任务时是 `idle`（客户端据此只更新基线，不跳页）；
/// 2. 本机截屏识别中 → 完成，端点跟着走，且 `done` 带回的 `session` 与 WS
///    `task_result` 的载荷**同构**（客户端直接复用同一条落地逻辑）；
/// 3. 没带 token 是 401（与其它端点一致）。
///
/// 另外始终带上主机当前合集：安卓端在 WS 连不上时靠它把状态行从
/// 「电脑未连接」改回「已连接 · 合集名」。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;
  const serverDeviceId = 'windows-local';
  const clientDeviceId = 'android-device-1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: serverDeviceId);
    await repo.init();
    imageDir = await Directory.systemTemp.createTemp('m15-poll-');
    final store = DirectoryImageStore(imageDir.path);
    server = QuizSyncServer(
      repo: repo,
      imageStore: store,
      executor: ServerTaskExecutor(
        repo: repo,
        engine: AnalysisEngine(
          provider: FakeAiProvider(
              File('test/fixtures/multi_and_judge.json').absolute.path),
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: serverDeviceId,
        ),
        imageStore: store,
        configProvider: () => const AiConfig(
            providerId: 'openai-compatible', apiKey: 'k', model: 'm'),
      ),
      deviceId: serverDeviceId,
      serverName: 'TEST-HOST',
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
    token = (await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
            .pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.0.0',
    )))
        .token;
    // 主机选中一个合集：端点要把它一起报给轮询端。
    await repo.upsertCollection(Collection(
      collectionId: 'c1',
      name: '期末复习',
      createdAt: 1,
      updatedAt: 1,
      updatedBy: serverDeviceId,
    ));
    await repo.setSetting(kActiveCollectionKey, 'c1');
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    await imageDir.delete(recursive: true);
  });

  ApiClient client() => ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);

  /// 服务端库里落一条已完成的会话 + 一道题 + 页序（模拟主机本机识别出结果）。
  Future<void> saveFinishedSession(String sessionId) async {
    await repo.upsertSession(Session(
      sessionId: sessionId,
      collectionId: 'c1',
      imageHash: 'h-$sessionId',
      sourceDevice: serverDeviceId,
      status: TaskState.done,
      questionCount: 1,
      createdAt: 1000,
      updatedAt: 2000,
      updatedBy: serverDeviceId,
    ));
    await repo.upsertQuestion(Question(
      questionId: 'q-$sessionId',
      sessionId: sessionId,
      ordinal: 0,
      questionNo: '12',
      stem: '主机识别出来的题干',
      type: QuestionType.single,
      choice: const ['B'],
      createdAt: 1000,
      updatedAt: 2000,
      updatedBy: serverDeviceId,
    ));
    await repo.setSessionImages(sessionId, ['h-$sessionId', 'h2-$sessionId']);
  }

  test('没有进行中的任务：返回 idle（客户端据此只更新基线，不跳页）', () async {
    final view = await client().fetchActiveTask();

    expect(view.status, 'idle');
    expect(view.idle, isTrue);
    expect(view.sessionId, isNull);
    expect(view.session, isNull);
    // 合集仍要报：WS 连不上时安卓端靠它把状态行改回「已连接 · 合集名」。
    expect(view.activeCollectionId, 'c1');
    expect(view.activeCollectionName, '期末复习');
  });

  test('本机截屏识别中 → done：端点跟着走，done 带回与 WS 同构的会话', () async {
    final api = client();

    // 1) 识别中：本地库里还没有这条会话，端点也必须报出状态与页数
    //    （否则安卓端会显示「没有任务」——用户看到的就是「安卓端没反应」）。
    server.notifyLocalSession('sess-poll-1', 'analyzing', imageCount: 2);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    var view = await api.fetchActiveTask();
    expect(view.status, 'analyzing');
    expect(view.taskId, 'sess-poll-1');
    expect(view.sessionId, 'sess-poll-1');
    expect(view.imageCount, 2, reason: '手机据此显示「2 张图片识别中…」');
    expect(view.session, isNull, reason: '还没结果就不带会话');
    expect(view.updatedAt, greaterThan(0),
        reason: '客户端靠它区分「同一个会话又出了新结果」');

    // 2) 出结果：服务端库里出现会话与题目，主机广播 done。
    await saveFinishedSession('sess-poll-1');
    server.notifyLocalSession('sess-poll-1', 'done');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    view = await api.fetchActiveTask();
    expect(view.status, 'done');
    expect(view.sessionId, 'sess-poll-1');
    expect(view.imageCount, 2);
    final session = view.session!;
    // 与 WS `task_result` 的载荷同构：安卓端把整个 map 交给 LiveUpdates 就行。
    expect(session['session_id'], 'sess-poll-1');
    expect(session['source_device'], serverDeviceId,
        reason: 'source_device 必须来自主机，客户端据此判断这是不是自己发起的识别');
    expect(session['status'], 'done');
    expect(session['image_hashes'], ['h-sess-poll-1', 'h2-sess-poll-1']);
    expect((session['questions'] as List), hasLength(1));
  });

  test('失败的任务：端点带上失败原因（客户端复用 task_failed 的语义）', () async {
    await repo.upsertSession(Session(
      sessionId: 'sess-fail',
      collectionId: 'c1',
      imageHash: 'h-fail',
      sourceDevice: serverDeviceId,
      status: TaskState.failed,
      errorCode: 'ai_timeout',
      errorMessage: 'AI 超时',
      createdAt: 1000,
      updatedAt: 2000,
      updatedBy: serverDeviceId,
    ));
    server.notifyLocalSession('sess-fail', 'failed');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final view = await client().fetchActiveTask();
    expect(view.status, 'failed');
    expect(view.message, 'AI 超时');
    expect(view.session, isNull, reason: '失败没有结果可回放');
  });

  test('未鉴权：401 unauthorized（与其它端点一致）', () async {
    await expectLater(
      ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '').fetchActiveTask(),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.code, 'code', 'unauthorized')),
    );
  });

  // ------------------------------------------------------------------
  // M17 第 5 条：Windows 删掉合集，安卓要跟着没
  // ------------------------------------------------------------------

  test('带上主机本地 ops 水位：主机一有本地改动就涨', () async {
    final api = client();
    final before = (await api.fetchActiveTask()).opsLamport;
    expect(before, greaterThan(0), reason: '建合集 / 选合集已经写过 op');

    await repo.upsertCollection(Collection(
      collectionId: 'c-new',
      name: '新合集',
      createdAt: 5,
      updatedAt: 5,
      updatedBy: serverDeviceId,
    ));
    final afterCreate = (await api.fetchActiveTask()).opsLamport;
    expect(afterCreate, greaterThan(before), reason: '水位不涨手机就不会去拉');

    await repo.deleteCollection('c-new');
    final afterDelete = (await api.fetchActiveTask()).opsLamport;
    expect(afterDelete, greaterThan(afterCreate), reason: '删除也是一条 op');
  });

  // ------------------------------------------------------------------
  // M18 第 4 条：主机把**活跃合集列表**直接放进状态探测里
  // ------------------------------------------------------------------

  test('状态探测带回主机的活跃合集列表（手机据此镜像，不再靠水位猜）', () async {
    final api = client();
    final before = await api.fetchActiveTask();
    expect(before.collections.map((c) => c.collectionId), contains('c1'));
    expect(before.collections.single.name, '期末复习');

    // 主机新建一个合集：**下一次探测**就能看到它（不依赖任何 op 拉取）。
    await repo.upsertCollection(Collection(
      collectionId: 'c-new',
      name: '新合集',
      createdAt: 5,
      updatedAt: 5,
      updatedBy: serverDeviceId,
    ));
    final after = await api.fetchActiveTask();
    expect(after.collections.map((c) => c.collectionId),
        containsAll(['c1', 'c-new']));

    // 主机删掉它：列表里立刻没有（但手机端由 `applyRemoteCollectionDeletes=false`
    // 决定不跟着删 —— 见 collection_features_test）。
    await repo.deleteCollection('c-new');
    final afterDelete = await api.fetchActiveTask();
    expect(afterDelete.collections.map((c) => c.collectionId),
        isNot(contains('c-new')));
  });

  test('手机镜像这份列表：主机新建的合集在手机本地出现（用户反馈的真问题）', () async {
    final phoneDb = QuizSyncDb(NativeDatabase.memory());
    addTearDown(phoneDb.close);
    final phone = CoreRepository(
      db: phoneDb,
      deviceId: clientDeviceId,
      applyRemoteCollectionDeletes: false,
    );
    await phone.init();
    final api = client();

    await repo.upsertCollection(Collection(
      collectionId: 'c-new',
      name: '新合集',
      createdAt: 5,
      updatedAt: 5,
      updatedBy: serverDeviceId,
    ));
    final view = await api.fetchActiveTask();
    // 手机本来一行合集都没有：主机识别的记录会全被算进「未分类」。
    expect(await phone.listCollections(), isEmpty);

    final changed = await phone.mirrorCollections(view.collections);
    expect(changed, 2, reason: 'c1 与 c-new 各插一行');
    expect((await phone.listCollections()).map((c) => c.collectionId),
        containsAll(['c1', 'c-new']),
        reason: '「windows 端的分类」要在手机历史里看得见');

    // 主机删掉 c-new：镜像**不删**本地的（用户要求不再跟着删）。
    await repo.deleteCollection('c-new');
    final after = await api.fetchActiveTask();
    expect(await phone.mirrorCollections(after.collections), 0);
    expect((await phone.listCollections()).map((c) => c.collectionId),
        contains('c-new'));
  });

  test('主机删除合集：客户端 pull-only 之后本地也没了这个合集', () async {
    final phoneDb = QuizSyncDb(NativeDatabase.memory());
    addTearDown(phoneDb.close);
    final phone = CoreRepository(db: phoneDb, deviceId: clientDeviceId);
    await phone.init();
    final engine = SyncEngine(repo: phone, localDeviceId: clientDeviceId);
    final api = client();

    Future<int> pullOnce() => engine.pullFromPeer(
          serverDeviceId,
          (since) => api.pullAllOps(
              sinceLamport: since, fromDevice: serverDeviceId),
        );

    // 第一次拉：手机看到主机的合集。
    await pullOnce();
    expect((await phone.listCollections()).map((c) => c.collectionId),
        contains('c1'));

    // 主机删掉它（Windows 的「新建/选择合集」页里的删除按钮走的就是这条）。
    await repo.deleteCollection('c1');
    // 轮询端点会把这个水位涨上去 → 手机据此拉一次（而不是干等下一次全量同步）。
    final view = await api.fetchActiveTask();
    expect(view.opsLamport, greaterThan(0));

    await pullOnce();
    expect((await phone.listCollections()).map((c) => c.collectionId),
        isNot(contains('c1')),
        reason: 'windows 没了，安卓也要跟着没了');
    // 合集下的会话**不级联删除**（与 Windows 一致：记录回到「未分类」）。
    expect(await phone.getCollection('c1'), isNull);
  });
}
