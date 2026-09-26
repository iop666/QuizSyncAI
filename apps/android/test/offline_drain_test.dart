import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_android/services/android_sync.dart';
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
    imageDir = await Directory.systemTemp.createTemp('m6-img-');
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

  /// 主机的任务必须归入一个已选中的合集（用户需求 8/12）。
  Future<String> selectCollection(String id) async {
    await serverRepo.upsertCollection(Collection(
      collectionId: id,
      name: '期末复习',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'server-1',
    ));
    await serverRepo.setSetting(kActiveCollectionKey, id);
    return id;
  }

  Future<({AndroidAppState app, QuizSyncDb db, AndroidSync sync, Directory dir})>
      client(String deviceId) async {
    final clientDb = QuizSyncDb(NativeDatabase.memory());
    final clientRepo = CoreRepository(db: clientDb, deviceId: deviceId);
    await clientRepo.init();
    final app = AndroidAppState(clientRepo, OfflineQueue(clientDb),
        MemorySecureStore(), SettingsController(MemoryKeyValueStore()));
    final localImages = await Directory.systemTemp.createTemp('m6-local-');
    final sync = AndroidSync(app: app, imageDir: localImages.path);
    return (app: app, db: clientDb, sync: sync, dir: localImages);
  }

  Future<PairingInfo> pair(AndroidAppState app, String deviceId) async {
    final probe = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final p = await probe.pair(PairRequest(
      code: server.pairingCode,
      deviceId: deviceId,
      deviceName: 't',
      platform: 'android',
      appVersion: '1.0.0',
    ));
    return PairingInfo(
      host: '127.0.0.1',
      port: port,
      token: p.token,
      serverDeviceId: 'server-1',
      serverName: 'T',
    );
  }

  /// 离线入队一张图（文件已落盘）。
  Future<String> enqueueOffline(
    AndroidSync sync,
    AndroidAppState app,
    int seed, {
    List<String>? imageHashes,
    String? collectionId,
  }) async {
    final jpeg = Uint8List.fromList([0xff, 0xd8, seed, 0xff, 0xd9]);
    final hash = sha256Hex(jpeg);
    await app.repo.upsertImage(ImageMeta(
        hash: hash,
        size: jpeg.length,
        mime: 'image/jpeg',
        createdAt: nowMs() + seed,
        uploadedBy: app.repo.deviceId));
    await sync.saveImageFile(hash, jpeg);
    await app.queue.enqueue(
        imageHash: hash,
        sourceDevice: app.repo.deviceId,
        now: nowMs() + seed,
        imageHashes: imageHashes,
        collectionId: collectionId);
    return hash;
  }

  test('离线队列：入队 → Windows 上线 → AndroidSync 按序补跑并上传（M6 任务 4）',
      timeout: const Timeout(Duration(seconds: 60)), () async {
    // 主机已选好合集。
    final collectionId = await selectCollection('c1');

    final c = await client('android-1');
    for (var i = 0; i < 3; i++) {
      await enqueueOffline(c.sync, c.app, i);
    }
    expect(await c.app.queue.queuedCount(), 3);

    // Windows「上线」：runFull 补跑。
    final r = await c.sync.runFull(await pair(c.app, 'android-1'));
    expect(r.drained, 3, reason: '三条按序补跑');
    expect(await c.app.queue.queuedCount(), 0);

    // 服务端收到 3 张图与 3 个任务，且都归到了当前合集。
    final images = await serverRepo.db.select(serverRepo.db.images).get();
    expect(images.length, 3);
    final tasks = await serverRepo.db.select(serverRepo.db.tasks).get();
    expect(tasks.length, 3);
    final sessions = await serverRepo.listSessions();
    expect(sessions.length, 3);
    for (final s in sessions) {
      expect(s.collectionId, collectionId,
          reason: '补跑的任务也要带上合集（用户需求 8）');
    }

    await c.dir.delete(recursive: true);
    await c.db.close();
  });

  test('主机未选合集：不烧死信——drained 为 0、任务仍 queued 且 attempts 不变',
      timeout: const Timeout(Duration(seconds: 60)), () async {
    // 故意不选合集：服务端 POST /tasks 会返回 409 no_active_collection。
    final c = await client('android-2');
    await enqueueOffline(c.sync, c.app, 7);
    expect(await c.app.queue.queuedCount(), 1);

    final r = await c.sync.runFull(await pair(c.app, 'android-2'));

    expect(r.drained, 0, reason: '整体性阻塞：一条都不算补跑成功');
    final queued = await c.app.queue.queuedTasks();
    expect(queued.length, 1, reason: '任务必须留在队列里等用户选合集');
    expect(queued.single.attempts, 0,
        reason: 'QueueRetryLater 不累加 attempts，避免烧成 queue_give_up');

    await c.dir.delete(recursive: true);
    await c.db.close();
  });

  test('多页入队补跑：页序与合集原样复原（用户需求 4/8）',
      timeout: const Timeout(Duration(seconds: 60)), () async {
    final collectionId = await selectCollection('c2');
    final c = await client('android-3');

    final h1 = sha256Hex(Uint8List.fromList([0xff, 0xd8, 1, 0xff, 0xd9]));
    final h2 = sha256Hex(Uint8List.fromList([0xff, 0xd8, 2, 0xff, 0xd9]));
    // 两页都先落盘（补跑要求原图可取）。
    var i = 0;
    for (final hash in [h1, h2]) {
      final jpeg = Uint8List.fromList([0xff, 0xd8, i + 1, 0xff, 0xd9]);
      await c.app.repo.upsertImage(ImageMeta(
          hash: hash,
          size: jpeg.length,
          mime: 'image/jpeg',
          createdAt: nowMs() + i,
          uploadedBy: c.app.repo.deviceId));
      await c.sync.saveImageFile(hash, jpeg);
      i++;
    }
    await c.app.queue.enqueue(
      imageHash: h1,
      sourceDevice: c.app.repo.deviceId,
      imageHashes: [h1, h2],
      collectionId: collectionId,
    );

    final r = await c.sync.runFull(await pair(c.app, 'android-3'));
    expect(r.drained, 1);

    final tasks = await serverRepo.db.select(serverRepo.db.tasks).get();
    expect(tasks.length, 1);
    final sessionId = tasks.single.sessionId;
    expect(sessionId, isNotNull);
    expect(await serverRepo.imageHashesOf(sessionId!), [h1, h2],
        reason: '两页按入队顺序复原');
    final session = await serverRepo.getSession(sessionId);
    expect(session!.collectionId, collectionId);

    await c.dir.delete(recursive: true);
    await c.db.close();
  });
}

Future<void> _noSleep(Duration d) async {}
