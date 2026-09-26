import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_android/services/android_sync.dart';
import 'package:quizsync_android/state/app_state.dart';

/// M50 真机实测的回归：手机上删掉一条记录后，本机 op 必须**立刻**推给主机，
/// 而不是等下次冷启动 App（实测：保持前台十几秒不推、切后台再回前台也不推，
/// 只有冷启动才把积压的 op 一起推上去 —— 用户观感是「手机上删了、电脑上还在」）。
void main() {
  late QuizSyncDb serverDb;
  late CoreRepository serverRepo;
  late QuizSyncServer server;
  late int port;
  late Directory imageDir;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    serverDb = QuizSyncDb(NativeDatabase.memory());
    serverRepo = CoreRepository(db: serverDb, deviceId: 'server-1');
    await serverRepo.init();
    imageDir = await Directory.systemTemp.createTemp('m50-img-');
    final provider = FakeAiProvider(
        File('../../packages/quizsync_core/test/fixtures/single_choice.json')
            .absolute.path);
    final engine = AnalysisEngine(
      provider: provider,
      cache: AnalysisCache(serverRepo),
      quota: QuotaGuard(serverDb),
      deviceId: 'server-1',
      retry: const RetryPolicy(sleeper: _noSleep),
    );
    final executor = ServerTaskExecutor(
      repo: serverRepo,
      engine: engine,
      imageStore: DirectoryImageStore(imageDir.path),
      configProvider: () => const AiConfig(apiKey: 'k', model: 'm'),
    );
    server = QuizSyncServer(
      repo: serverRepo,
      imageStore: DirectoryImageStore(imageDir.path),
      executor: executor,
      deviceId: 'server-1',
      serverName: 'T',
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await imageDir.delete(recursive: true);
  });

  test('手机上删除记录 → pushOpsOnly 立刻把删除推给主机', () async {
    // 主机侧先有一条识别记录（模拟电脑识别完同步过来的历史）。
    final session = await serverRepo.upsertSession(Session(
      sessionId: newUuidV4(),
      imageHash: 'h-1',
      sourceDevice: 'server-1',
      status: TaskState.done,
      questionCount: 1,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'server-1',
    ));
    await serverRepo.upsertQuestion(Question(
      questionId: newUuidV4(),
      sessionId: session.sessionId,
      ordinal: 0,
      stem: '题干',
      type: QuestionType.blank,
      answerText: '答案',
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'server-1',
    ));

    // 客户端：配对 → 拉一次（本地就有这条记录了）。
    final clientDb = QuizSyncDb(NativeDatabase.memory());
    addTearDown(clientDb.close);
    final clientRepo = CoreRepository(db: clientDb, deviceId: 'android-1');
    await clientRepo.init();
    final app = AndroidAppState(clientRepo, OfflineQueue(clientDb),
        MemorySecureStore(), SettingsController(MemoryKeyValueStore()));
    final sync = AndroidSync(app: app);
    final probe = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final p = await probe.pair(PairRequest(
      code: server.pairingCode,
      deviceId: 'android-1',
      deviceName: 't',
      platform: 'android',
      appVersion: '1.2.0',
    ));
    final pairing = PairingInfo(
      host: '127.0.0.1',
      port: port,
      token: p.token,
      serverDeviceId: 'server-1',
      serverName: 'T',
    );
    await sync.runFull(pairing);
    expect(await clientRepo.getSession(session.sessionId), isNotNull,
        reason: '前置条件：这条记录已经同步到手机');

    // 用户在手机上删除它：本地库立刻没了，但主机还不知道。
    await clientRepo.deleteSession(session.sessionId);
    expect(await clientRepo.getSession(session.sessionId), isNull);
    expect(await serverRepo.getSession(session.sessionId), isNotNull,
        reason: '删除是本机动作，不推之前主机不该变');

    // 「写完即推」：一条 op 都不该留在本地。
    final pushed = await sync.pushOpsOnly(pairing);
    expect(pushed, greaterThan(0), reason: '应当真的推了 op');
    expect(await serverRepo.getSession(session.sessionId), isNull,
        reason: '主机必须立刻看到删除（不等手机下次冷启动）');
  });
}

/// 测试里不真的等待退避。
Future<void> _noSleep(Duration d) async {}
