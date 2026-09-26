import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M47：`/sync/ops` 与 WS 的 `push_ops` 原来只拒绝「冒充主机自己」的 op，
/// 任何已配对设备都能拿**别的设备**的 device_id 配上任意大的 lamport 改写对方
/// 的数据（LWW 下高 lamport 必赢），主机还会把它当成真事再同步给所有对端。
/// 现在 op 的归属必须等于**认证设备**。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;

  const serverDeviceId = 'windows-local';
  const callerId = 'android-device-1';
  const otherId = 'android-device-2';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: serverDeviceId);
    await repo.init();
    imageDir = await Directory.systemTemp.createTemp('m47-ops-');
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
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    token = (await api.pair(PairRequest(
      code: server.pairingCode,
      deviceId: callerId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.1.0',
    )))
        .token;
    // 第二台设备也真的配对（不是凭空编的 id）。
    await api.pair(PairRequest(
      code: server.pairingCode,
      deviceId: otherId,
      deviceName: 'Mi 11',
      platform: 'android',
      appVersion: '1.1.0',
    ));
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    await imageDir.delete(recursive: true);
  });

  Map<String, dynamic> sessionFields(String id, String source) =>
      sessionFieldMap(Session(
        sessionId: id,
        imageHash: 'h-$id',
        sourceDevice: source,
        status: TaskState.done,
        questionCount: 0,
        createdAt: 1000,
        updatedAt: 1000,
        updatedBy: source,
      ));

  SyncOp op(String id, String deviceId, {int lamport = 9999}) => SyncOp(
        opId: 'op-$id-$deviceId',
        deviceId: deviceId,
        lamport: lamport,
        entity: SyncEntity.session,
        entityId: id,
        opType: SyncOpType.upsert,
        fields: sessionFields(id, deviceId),
        createdAt: 5000,
      );

  test('HTTP：冒充别人的 device_id 的 op 被拒绝（应用数为 0、数据没被写）', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);

    expect(await api.pushOps([op('s-forged', otherId)]), 0,
        reason: '认证设备是 android-device-1，不能替 android-device-2 写数据');
    expect(await repo.getSession('s-forged', includeDeleted: true), isNull);

    // 自己的 op 照常应用。
    expect(await api.pushOps([op('s-mine', callerId, lamport: 10)]), 1);
    expect(await repo.getSession('s-mine', includeDeleted: true), isNotNull);

    // 主机自己的 device_id 依旧只是「跳过」，不算违规。
    expect(await api.pushOps([op('s-host', serverDeviceId)]), 0);
    expect(await repo.getSession('s-host', includeDeleted: true), isNull);
  });

  test('WS：同一条规则（手机走的是这条通道）', () async {
    final socket = SyncSocket(
      wsUri: Uri.parse('ws://127.0.0.1:$port/ws'),
      token: token,
      deviceId: callerId,
    );
    await socket.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    socket.sendPushOps([op('s-forged-ws', otherId)]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await repo.getSession('s-forged-ws', includeDeleted: true), isNull,
        reason: 'WS 通道同样不能替别的设备写数据');

    socket.sendPushOps([op('s-mine-ws', callerId, lamport: 11)]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await repo.getSession('s-mine-ws', includeDeleted: true), isNotNull,
        reason: '自己的 op 不能一起挡掉');

    await socket.dispose();
  });
}
