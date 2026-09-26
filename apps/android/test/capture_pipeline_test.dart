import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_android/services/android_capture_controller.dart';
import 'package:quizsync_android/services/capture_source.dart';
import 'package:quizsync_android/state/app_state.dart';

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
    // 用户需求 12：主机必须先选一个合集，否则任务会被 409 拒绝。
    await serverRepo.upsertCollection(Collection(
      collectionId: 'c1',
      name: '期末复习',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await serverRepo.setSetting(kActiveCollectionKey, 'c1');
    imageDir = await Directory.systemTemp.createTemp('m5-img-');

    final provider = FakeAiProvider(
        File('../../packages/quizsync_core/test/fixtures/multi_and_judge.json')
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
      configProvider: () =>
          const AiConfig(apiKey: 'k', model: 'm'),
    );
    server = QuizSyncServer(
      repo: serverRepo,
      imageStore: DirectoryImageStore(imageDir.path),
      executor: executor,
      deviceId: 'server-1',
      serverName: 'TEST',
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await imageDir.delete(recursive: true);
  });

  /// 建一个已配对的客户端 App。
  Future<({AndroidAppState app, QuizSyncDb db})> client(String deviceId) async {
    final clientDb = QuizSyncDb(NativeDatabase.memory());
    final clientRepo = CoreRepository(db: clientDb, deviceId: deviceId);
    await clientRepo.init();
    final app = AndroidAppState(clientRepo, OfflineQueue(clientDb),
        MemorySecureStore(), SettingsController(MemoryKeyValueStore()));
    final probe = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final pair = await probe.pair(PairRequest(
      code: server.pairingCode,
      deviceId: deviceId,
      deviceName: '测试手机',
      platform: 'android',
      appVersion: '1.0.0',
    ));
    await app.savePairing(PairingInfo(
      host: '127.0.0.1',
      port: port,
      token: pair.token,
      serverDeviceId: pair.serverDeviceId,
      serverName: pair.serverName,
    ));
    return (app: app, db: clientDb);
  }

  test('悬浮球截屏 → 上传 → 分析 → 本地入库 → 前台跳结果页（FakeCaptureSource 全链路）',
      timeout: const Timeout(Duration(seconds: 60)), () async {
    final c = await client('android-1');
    final jpeg = Uint8List.fromList([
      0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46,
      0x00, 0x01, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9,
    ]);
    final captureSource = FakeCaptureSource(jpeg);
    String? resultSession;
    final messages = <String>[];
    final controller = AndroidCaptureController(
      app: c.app,
      captureSource: captureSource,
      onResultReady: (sessionId) => resultSession = sessionId,
      onMessage: messages.add,
    );

    await controller.captureAndUpload();

    expect(captureSource.captureCount, 1, reason: '悬浮球单击触发一次截屏');
    expect(resultSession, isNotNull, reason: '前台应直接跳结果页');
    final questions = await c.app.repo.questionsOfSession(resultSession!);
    expect(questions.length, 2, reason: '结果落本地库，历史可离线查看');
    expect(computeHighlight(questions[0]).optionLabels, {'A', 'C', 'D'});
    expect(messages.where((m) => m.contains('失败')), isEmpty);

    // 任务归到了主机当前的合集里（用户需求 8/12）。
    final session = await c.app.repo.getSession(resultSession!);
    expect(session!.collectionId, 'c1');

    await c.db.close();
  });

  test('主机未选合集：拦住上传并提示统一文案（不静默失败）', () async {
    final c = await client('android-2');
    // 主机把合集取消掉。
    await serverRepo.setSetting(kActiveCollectionKey, '');

    var captures = 0;
    final messages = <String>[];
    final controller = AndroidCaptureController(
      app: c.app,
      captureSource: _CountingCaptureSource(() => captures++),
      onResultReady: (_) => fail('不应该产生结果'),
      onMessage: messages.add,
    );

    await controller.captureAndUpload();

    expect(captures, 0, reason: '没确认合集前不允许截屏上传');
    expect(messages, contains('请先在电脑上选择任务合集'));
    final images = await serverRepo.db.select(serverRepo.db.images).get();
    expect(images, isEmpty, reason: '被拦下就不该有上传');
    await c.db.close();
  });

  test('长按加页 + 短按结束：一次多页任务（用户需求 4/11）',
      timeout: const Timeout(Duration(seconds: 60)), () async {
    final c = await client('android-3');
    final source = _SequencedCaptureSource();
    String? resultSession;
    final messages = <String>[];
    final controller = AndroidCaptureController(
      app: c.app,
      captureSource: source,
      onResultReady: (sessionId) => resultSession = sessionId,
      onMessage: messages.add,
    );

    // 长按第一页 → 立即上传，但还没有任务。
    await controller.onBallLongPress();
    expect(controller.multiPage.active, isTrue);
    expect(controller.multiPage.pageCount, 1);
    var tasks = await serverRepo.db.select(serverRepo.db.tasks).get();
    expect(tasks, isEmpty, reason: '还在收集页，不能提前建任务');

    // 再长按加第二页。
    await controller.onBallLongPress();
    expect(controller.multiPage.pageCount, 2);

    // 短按 = 结束并提交已抓的页（M49：不再补截一页）。
    final result = await controller.onBallTap();
    expect(result.ok, isTrue, reason: messages.join('；'));
    expect(controller.multiPage.active, isFalse);

    tasks = await serverRepo.db.select(serverRepo.db.tasks).get();
    expect(tasks.length, 1, reason: '两次长按加一次短按只产生一个任务');
    expect(resultSession, isNotNull);

    final pages = await serverRepo.imageHashesOf(resultSession!);
    expect(pages.length, 2, reason: '2 次长按 = 2 页（收尾的短按只提交，不截新图）');
    expect(pages.toSet().length, 2, reason: '两页是不同的图');

    await c.db.close();
  });

  test('截屏失败（FLAG_SECURE 黑图/无帧）→ 提示禁止截屏 + 不上传', () async {
    final c = await client('android-4');
    final messages = <String>[];
    final controller = AndroidCaptureController(
      app: c.app,
      captureSource: _NullCaptureSource(),
      onResultReady: (_) => fail('不应有结果'),
      onMessage: messages.add,
    );
    await controller.captureAndUpload();

    expect(
      messages.any((m) => m.contains('禁止截屏') && m.contains('相册')),
      isTrue,
      reason: '黑图/取帧失败 → 提示「该应用禁止截屏」+ 从相册选图',
    );
    await c.db.close();
  });
}

Future<void> _noSleep(Duration d) async {}

/// 模拟 FLAG_SECURE / 无帧的采集源。
class _NullCaptureSource implements CaptureSource {
  @override
  Future<Uint8List?> capture() async => null;

  @override
  Future<CaptureAvailability> availability() async =>
      const CaptureAvailability(main: true);

  @override
  Future<bool> requestAuthorization() async => true;
}

/// 记录「是否被调过截屏」的采集源（断言被拦下时根本没截屏）。
class _CountingCaptureSource implements CaptureSource {
  _CountingCaptureSource(this.onCapture);

  final void Function() onCapture;

  @override
  Future<Uint8List?> capture() async {
    onCapture();
    return Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  Future<CaptureAvailability> availability() async =>
      const CaptureAvailability(main: true);

  @override
  Future<bool> requestAuthorization() async => true;
}

/// 每次截屏返回不同字节的采集源（多页识别的每页 hash 必须不同）。
class _SequencedCaptureSource implements CaptureSource {
  int _i = 0;

  @override
  Future<Uint8List?> capture() async {
    _i++;
    return Uint8List.fromList([0xff, 0xd8, _i, 0x11, 0xff, 0xd9]);
  }

  @override
  Future<CaptureAvailability> availability() async =>
      const CaptureAvailability(main: true);

  @override
  Future<bool> requestAuthorization() async => true;
}
