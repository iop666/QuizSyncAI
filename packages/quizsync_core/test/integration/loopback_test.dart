import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// protocol.md 第 6 节的环形验证（M4 验收基础）：
/// 无设备、无网络外联（仅 127.0.0.1 回环）跑通配对 → 上传 → 任务 →
/// WS 结果 → 双端 sync_ops → 增量拉取 → 吊销。
void main() {
  late QuizSyncDb serverDb;
  late CoreRepository serverRepo;
  late QuizSyncDb clientDb;
  late CoreRepository clientRepo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;
  late ApiClient api;
  final serverDeviceId = 'server-device-1';
  final clientDeviceId = 'android-device-1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    serverDb = QuizSyncDb(NativeDatabase.memory());
    serverRepo = CoreRepository(db: serverDb, deviceId: serverDeviceId);
    await serverRepo.init();
    clientDb = QuizSyncDb(NativeDatabase.memory());
    clientRepo = CoreRepository(db: clientDb, deviceId: clientDeviceId);
    await clientRepo.init();
    imageDir = await Directory.systemTemp.createTemp('quizsync-images-');

    final provider =
        FakeAiProvider(File('test/fixtures/multi_and_judge.json').absolute.path);
    final engine = AnalysisEngine(
      provider: provider,
      cache: AnalysisCache(serverRepo),
      quota: QuotaGuard(serverDb),
      deviceId: serverDeviceId,
      retry: const RetryPolicy(sleeper: _noSleep),
    );
    final executor = ServerTaskExecutor(
      repo: serverRepo,
      engine: engine,
      imageStore: DirectoryImageStore(imageDir.path),
      configProvider: () => const AiConfig(
        providerId: 'openai-compatible',
        apiKey: 'test-key',
        model: 'test-model',
      ),
    );
    server = QuizSyncServer(
      repo: serverRepo,
      imageStore: DirectoryImageStore(imageDir.path),
      executor: executor,
      deviceId: serverDeviceId,
      serverName: 'TEST-HOST',
      // 1. 启动服务端，监听随机端口（preferredPort: 0 = 系统分配）。
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await clientDb.close();
    await imageDir.delete(recursive: true);
  });

  test('环形验证 9 步（protocol.md 第 6 节）', timeout: const Timeout(Duration(seconds: 60)),
      () async {
    // 2. 获取 /info → 断言 protocol_version。
    final info = await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
        .fetchInfo();
    expect(info.protocolVersion, 1);
    expect(info.platform, 'windows');
    expect(info.aiConfigured, isTrue);
    // M9：设置页「连接状态」读的就是这两个只读 getter（不改协议）。
    expect(server.connectedCount, 0, reason: '没有设备连着时是 0');
    expect(server.connectedDeviceIds, isEmpty);
    expect(info.capabilities,
        containsAll(['analyze', 'sync', 'image_fetch', 'collections', 'multipage']));

    // 无 token 访问受保护端点 → 401 unauthorized。
    final noAuth = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    try {
      await noAuth.createTask(
          taskId: 'x', imageHash: 'y', sourceDevice: clientDeviceId);
      fail('应返回 401');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 401);
      expect(e.code, 'unauthorized');
    }

    // 3. 用配对码 POST /pair → 拿到 token。
    final pairResp = await noAuth.pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel 7',
      platform: 'android',
      appVersion: '1.0.0',
    ));
    token = pairResp.token;
    expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(pairResp.serverDeviceId, serverDeviceId);
    expect(pairResp.serverName, 'TEST-HOST');
    api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);

    // 错误配对码 → 401 invalid_code。
    try {
      await noAuth.pair(PairRequest(
        code: '000000',
        deviceId: 'intruder',
        deviceName: 'x',
        platform: 'android',
        appVersion: '1.0.0',
      ));
      fail('应返回 401');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 401);
      expect(e.code, 'invalid_code');
    }

    // 4. 构造一张假 JPEG → POST /images → 拿到 hash。
    final jpegBytes = Uint8List.fromList([
      0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46,
      0x00, 0x01, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9,
    ]);
    final uploaded = await api.uploadImage(jpegBytes);
    expect(uploaded.imageHash, sha256Hex(jpegBytes));
    expect(uploaded.existed, isFalse);
    // 重复上传 → existed: true（按 hash 幂等）。
    final again = await api.uploadImage(jpegBytes);
    expect(again.existed, isTrue);

    // 5. POST /tasks（假 AI provider 返回 fixture）→ 202 queued。
    // 先连 WS，再建任务以便收到推送。
    final ws = SyncSocket(
      wsUri: Uri.parse('ws://127.0.0.1:$port/ws'),
      token: token,
      deviceId: clientDeviceId,
    );
    final results = <Map<String, dynamic>>[];
    final updates = <String>[];
    final sub = ws.messages.listen((msg) {
      if (msg['type'] == 'task_result') results.add(msg);
      if (msg['type'] == 'task_update') updates.add(msg['status'].toString());
    });
    await ws.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.connectedCount, 1, reason: 'WS 连上后连接状态应为「已连接」');
    expect(server.connectedDeviceIds, contains(clientDeviceId));

    final taskId = newUuidV4();

    // 用户需求 8/12：主机未选合集时必须 409，而不是把任务塞进「未分类」。
    try {
      await api.createTask(
        taskId: taskId,
        imageHash: uploaded.imageHash,
        sourceDevice: clientDeviceId,
      );
      fail('未选合集时应返回 409');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 409);
      expect(e.code, 'no_active_collection');
    }

    // 新建并选中合集 → /info 反映，任务被接受。
    final collection = await serverRepo.upsertCollection(Collection(
      collectionId: newUuidV4(),
      name: '环形验证合集',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: serverDeviceId,
    ));
    await serverRepo.setSetting(kActiveCollectionKey, collection.collectionId);
    final info2 = await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
        .fetchInfo();
    expect(info2.activeCollectionId, collection.collectionId);
    expect(info2.activeCollectionName, '环形验证合集');
    expect(info2.hasActiveCollection, isTrue);

    final created = await api.createTask(
      taskId: taskId,
      imageHash: uploaded.imageHash,
      sourceDevice: clientDeviceId,
    );
    expect(created.status, anyOf('queued', 'analyzing', 'done'));

    // 6. 等 WS 收到 task_result → 断言题目数量、字段、标绿所需字段齐全。
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (results.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(results, isNotEmpty, reason: '应在超时前收到 task_result');
    final sessionJson = Map<String, dynamic>.from(results.first['session'] as Map);
    final questionsJson = sessionJson['questions'] as List;
    expect(questionsJson.length, 2);
    final q0 = Question.fromJson(Map<String, dynamic>.from(questionsJson[0]));
    final q1 = Question.fromJson(Map<String, dynamic>.from(questionsJson[1]));
    expect(q0.type, QuestionType.multi);
    expect(q0.choice, isNotEmpty);
    expect(computeHighlight(q0).optionLabels, {'A', 'C', 'D'}, reason: '标绿所需字段齐全');
    expect(computeHighlight(q1).optionLabels, {'对'});
    expect(sessionJson['status'], 'done');

    // GET /tasks/{id} 与 WS 结果一致（断线兜底路径）。
    final taskView = await api.getTask(taskId);
    expect(taskView.done, isTrue);
    expect(taskView.sessionId, sessionJson['session_id']);
    expect(taskView.questions!.length, 2);

    // 7. 断言两端数据库都生成了对应的 sync_ops。
    // 服务端（分析方）：
    final serverOps = await serverDb.select(serverDb.syncOps).get();
    expect(serverOps.length, greaterThanOrEqualTo(4), reason: '服务端至少有 image/session/question ops');
    // 客户端（收到结果后本地入库，Android 端行为模拟）：
    final session = Session.fromJson(sessionJson);
    await clientRepo.upsertSession(session.copyWith(taskId: taskId));
    await clientRepo.upsertImage(ImageMeta(
      hash: uploaded.imageHash,
      size: uploaded.size,
      mime: 'image/jpeg',
      createdAt: nowMs(),
      uploadedBy: clientDeviceId,
    ));
    for (final q in [q0, q1]) {
      await clientRepo.upsertQuestion(
          q.copyWith(sessionId: session.sessionId, createdAt: nowMs(), updatedAt: nowMs(), updatedBy: clientDeviceId));
    }
    final clientOps = await clientDb.select(clientDb.syncOps).get();
    expect(clientOps.length, greaterThanOrEqualTo(4));
    expect(clientOps.every((o) => o.deviceId == clientDeviceId), isTrue);

    // 8. GET /sync/ops 增量拉取 → 不重复、不丢。
    final pulled =
        await api.pullAllOps(sinceLamport: 0, fromDevice: serverDeviceId);
    expect(pulled.length, serverOps.length, reason: '不丢');
    expect(pulled.map((o) => o.opId).toSet().length, pulled.length,
        reason: '不重复');
    // 应用到客户端库：幂等（重复应用被 op_id 去重）。
    for (final op in pulled) {
      await clientRepo.applyRemoteOp(op);
    }
    for (final op in pulled) {
      await clientRepo.applyRemoteOp(op);
    }
    final applied = await clientDb.select(clientDb.syncOps).get();
    expect(applied.map((o) => o.opId).toSet().length,
        applied.map((o) => o.opId).length,
        reason: '重复 op 无副作用');
    // 拉第二次（since 已推进）→ 没有新 op。
    final watermark = pulled.fold<int>(0, (m, o) => o.lamport > m ? o.lamport : m);
    final secondPull =
        await api.pullAllOps(sinceLamport: watermark, fromDevice: serverDeviceId);
    expect(secondPull, isEmpty);

    // 9. 吊销设备 → 再请求 → 401 revoked。
    await api.revokeDevice(clientDeviceId);
    try {
      await api.getTask(taskId);
      fail('吊销后应返回 401');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 401);
      expect(e.code, 'revoked');
    }

    await sub.cancel();
    await ws.dispose();
    // 断开后连接数归零：设置页据此从「已连接」回到「等待手机连接」。
    final dropDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (server.connectedCount != 0 && DateTime.now().isBefore(dropDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(server.connectedCount, 0);
  });

  test('多页任务与「重新生成」走完整协议（用户需求 4/7）', () async {
    final noAuth = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final pairResp = await noAuth.pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel 7',
      platform: 'android',
      appVersion: '1.0.0',
    ));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: pairResp.token);

    // 合集先建好并选中（否则 409）。
    final collection = await serverRepo.upsertCollection(Collection(
      collectionId: newUuidV4(),
      name: '多页合集',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: serverDeviceId,
    ));
    await serverRepo.setSetting(kActiveCollectionKey, collection.collectionId);

    // 上传两页 + 连 WS。
    final p1 = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final p2 = Uint8List.fromList(List.generate(32, (i) => 200 - i));
    final up1 = await api.uploadImage(p1);
    final up2 = await api.uploadImage(p2);

    final ws = SyncSocket(
      wsUri: Uri.parse('ws://127.0.0.1:$port/ws'),
      token: pairResp.token,
      deviceId: clientDeviceId,
    );
    final results = <Map<String, dynamic>>[];
    ws.messages.listen((m) {
      if (m['type'] == 'task_result') results.add(m);
    });
    await ws.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final taskId = newUuidV4();
    final created = await api.createTask(
      taskId: taskId,
      imageHash: up1.imageHash,
      imageHashes: [up1.imageHash, up2.imageHash],
      collectionId: collection.collectionId,
      sourceDevice: clientDeviceId,
    );
    expect(created.status, anyOf('queued', 'analyzing'));
    final sessionId = created.sessionId!;

    var deadline = DateTime.now().add(const Duration(seconds: 30));
    while (results.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(results, isNotEmpty, reason: '多页任务也应收到 task_result');
    final sessionJson =
        Map<String, dynamic>.from(results.first['session'] as Map);
    expect(sessionJson['image_hashes'],
        [up1.imageHash, up2.imageHash], reason: '页序原样带回');
    expect(sessionJson['image_count'], 2);
    expect(sessionJson['collection_id'], collection.collectionId);

    // 会话页序落库。
    expect(await serverRepo.imageHashesOf(sessionId),
        [up1.imageHash, up2.imageHash]);

    // 「重新生成」：新任务 + 新会话，仍带两页。
    results.clear();
    final again = await api.reanalyzeSession(sessionId);
    expect(again.status, anyOf('queued', 'analyzing', 'done'));
    final newSessionId = again.sessionId!;
    expect(newSessionId, isNot(sessionId));
    deadline = DateTime.now().add(const Duration(seconds: 30));
    while (results.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(results, isNotEmpty, reason: '重新生成也要有结果');
    expect(await serverRepo.imageHashesOf(newSessionId),
        [up1.imageHash, up2.imageHash]);
  });

  test('超过页数硬上限被拒（too_many_pages）', () async {
    final noAuth = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final pairResp = await noAuth.pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel 7',
      platform: 'android',
      appVersion: '1.0.0',
    ));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: pairResp.token);
    final collection = await serverRepo.upsertCollection(Collection(
      collectionId: newUuidV4(),
      name: '上限合集',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: serverDeviceId,
    ));
    await serverRepo.setSetting(kActiveCollectionKey, collection.collectionId);

    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final up = await api.uploadImage(bytes);
    try {
      await api.createTask(
        taskId: newUuidV4(),
        imageHash: up.imageHash,
        imageHashes:
            List.generate(kHardMaxPagesPerTask + 1, (_) => up.imageHash),
        sourceDevice: clientDeviceId,
      );
      fail('超过硬上限应被拒');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 400);
      expect(e.code, 'too_many_pages');
    }
  });

  test('配对码过期与限速', () async {
    final noAuth = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    // 用错误码连续触发限速（每分钟 5 次）。
    var rateLimited = false;
    for (var i = 0; i < 8 && !rateLimited; i++) {
      try {
        await noAuth.pair(PairRequest(
          code: '000000',
          deviceId: 'x$i',
          deviceName: 'x',
          platform: 'android',
          appVersion: '1.0.0',
        ));
      } on ApiClientException catch (e) {
        if (e.code == 'rate_limited') {
          rateLimited = true;
          expect(e.statusCode, 429);
          expect(e.retryAfterSeconds, greaterThan(0));
        }
      }
    }
    expect(rateLimited, isTrue, reason: '连续尝试应触发 429 rate_limited');
  });
}

Future<void> _noSleep(Duration d) async {}
