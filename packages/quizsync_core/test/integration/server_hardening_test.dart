import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M47 的服务端加固（C 批）：
/// - **426**：主版本不一致要挡住（`protocol.md` 2.1），不带版本头的请求放行；
/// - **409**：同 device_id 重新配对（`protocol.md` 2.2），body 里照样给新 token；
/// - **snapshot 分页**（`data-model.md` 2.9），不再一次性把全库读进内存；
/// - **任务队列深度上限**，免得一个客户端连点把主机灌满；
/// - **陌生设备尝试连接**要有计数（`SPEC.md` §8 的安全提示数据源），
///   且配对失败计数与锁定期**跨重启保留**。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;

  const serverDeviceId = 'windows-local';
  const clientDeviceId = 'android-device-1';

  QuizSyncServer buildServer({int maxQueueDepth = 20}) {
    final store = DirectoryImageStore(imageDir.path);
    return QuizSyncServer(
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
      options: QuizSyncServerOptions(
        preferredPort: 0,
        maxQueueDepth: maxQueueDepth,
        pairFailureLockThreshold: 2,
        pairLockout: const Duration(minutes: 5),
      ),
    );
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: serverDeviceId);
    await repo.init();
    imageDir = await Directory.systemTemp.createTemp('m47-hardening-');
    server = buildServer();
    port = await server.start();
    token = (await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
            .pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.1.0',
    )))
        .token;
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    await imageDir.delete(recursive: true);
  });

  /// 不带 `X-QS-Client-Version` 的裸请求（老客户端 / curl）。
  Future<int> rawInfoStatus() async {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/api/v1/info'));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Uint8List jpeg() => Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 1, 2, 3, 0xff, 0xd9]);

  test('主版本不一致 → 426；不带版本头的老客户端照常放行', () async {
    final newer = ApiClient(
        baseUrl: 'http://127.0.0.1:$port', token: token, appVersion: '2.0.0');
    await expectLater(
      newer.uploadImage(jpeg()),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 426)
          .having((e) => e.code, 'code', 'version_mismatch')),
    );

    // 同主版本照常；没有这个头（老客户端 / curl）也照常。
    final same = ApiClient(
        baseUrl: 'http://127.0.0.1:$port', token: token, appVersion: '1.9.9');
    expect((await same.uploadImage(jpeg())).imageHash, isNotEmpty);
    expect(await rawInfoStatus(), 200);
  });

  test('同 device_id 重新配对 → 409 already_paired，token 仍然可用', () async {
    final client = HttpClient();
    late int status;
    late Map<String, dynamic> body;
    try {
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/pair'));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode(PairRequest(
        code: server.pairingCode,
        deviceId: clientDeviceId,
        deviceName: 'Pixel',
        platform: 'android',
        appVersion: '1.1.0',
      ).toJson()));
      final res = await req.close();
      status = res.statusCode;
      body = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
    expect(status, 409);
    expect(body['already_paired'], isTrue);
    expect((body['token'] as String).isNotEmpty, isTrue, reason: 'body 里要给新 token');

    // ApiClient 把 409 也当成功（否则用户「重新配对」会看到莫名其妙的错误），
    // 而且新 token 能直接用。
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final again = await api.pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.1.0',
    ));
    expect((await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: again.token)
            .uploadImage(jpeg()))
        .imageHash,
        isNotEmpty);
  });

  test('snapshot 按会话分页（limit / offset / has_more）', () async {
    for (var i = 0; i < 3; i++) {
      await repo.upsertSession(Session(
        sessionId: 's$i',
        imageHash: 'h$i',
        sourceDevice: serverDeviceId,
        status: TaskState.done,
        questionCount: 1,
        createdAt: 1000 + i,
        updatedAt: 1000 + i,
        updatedBy: serverDeviceId,
      ));
    }

    /// 没有客户端用这个端点，测试直接打裸 HTTP（免得多出一个公开 API）。
    Future<Map<String, dynamic>> snapshot({int? limit, int? offset}) async {
      final client = HttpClient();
      try {
        final uri = Uri.parse('http://127.0.0.1:$port/api/v1/sync/snapshot')
            .replace(queryParameters: {
          if (limit != null) 'limit': '$limit',
          if (offset != null) 'offset': '$offset',
        });
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $token');
        final res = await req.close();
        expect(res.statusCode, 200);
        return jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
      } finally {
        client.close(force: true);
      }
    }

    List<String> idsOf(Map<String, dynamic> page) => [
          for (final s in page['sessions'] as List)
            (s as Map)['session_id'].toString()
        ];

    final first = await snapshot(limit: 2);
    expect(idsOf(first), hasLength(2));
    expect(first['has_more'], isTrue);
    expect(first['next_offset'], 2);

    final rest = await snapshot(limit: 2, offset: first['next_offset'] as int);
    expect(idsOf(rest), hasLength(1), reason: '第二页只剩一条');
    expect(rest['has_more'], isFalse);
    expect({...idsOf(first), ...idsOf(rest)}, {'s0', 's1', 's2'},
        reason: '两页合起来正好是全量（不重不漏）');
  });

  test('任务队列深度上限：满了回 429 queue_full', () async {
    await server.stop();
    server = buildServer(maxQueueDepth: 1);
    port = await server.start();
    token = (await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
            .pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.1.0',
    )))
        .token;

    final c = await repo.upsertCollection(Collection(
      collectionId: 'c-1',
      name: '合集',
      createdAt: 1,
      updatedAt: 1,
      updatedBy: serverDeviceId,
    ));
    await repo.setSetting(kActiveCollectionKey, c.collectionId);

    // 队列里先占一条（排队中、还没被跑掉）。
    await OfflineQueue(db).enqueue(
        imageHash: 'queued-1', sourceDevice: clientDeviceId);

    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);
    final uploaded = await api.uploadImage(jpeg());
    await expectLater(
      api.createTask(
        taskId: 't-overflow',
        imageHash: uploaded.imageHash,
        sourceDevice: clientDeviceId,
      ),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.code, 'code', 'queue_full')),
    );
  });

  test('在线判据：HTTP 轮询也算在线，认不出的 token 不算（用户实测反馈）', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);
    expect(server.activeDeviceCount, 0);

    // 手机端在前台时每秒问一次 `/tasks/active`（走 HTTP、**不建 WS**）——
    // 这种设备也算在线，否则设置页一直显示「等待手机连接」。
    await api.uploadImage(jpeg());
    expect(server.activeDeviceCount, 1);
    expect(server.activeDeviceIds, contains(clientDeviceId));

    // 认不出的 token 不参与在线计数（也不该在设置页刷提示）。
    final bogus = ApiClient(
        baseUrl: 'http://127.0.0.1:$port', token: 'deadbeef' * 4);
    await expectLater(bogus.uploadImage(jpeg()),
        throwsA(isA<ApiClientException>()));
    expect(server.activeDeviceCount, 1, reason: '无效 token 不该被算成一台在线设备');
  });

  test('配对失败计数与锁定期跨重启保留', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    Future<void> wrongCode() async {
      try {
        await api.pair(PairRequest(
          code: '000000',
          deviceId: 'attacker-1',
          deviceName: 'X',
          platform: 'android',
          appVersion: '1.1.0',
        ));
      } catch (_) {}
    }

    await wrongCode();
    await wrongCode(); // 阈值 2 → 触发锁定
    final locked = await repo.getSetting('pair_locked_until');
    expect(int.tryParse(locked ?? '') ?? 0, greaterThan(0),
        reason: '锁定期要落库');

    // 重启服务端（同一份库）：锁定仍然生效。
    await server.stop();
    server = buildServer();
    port = await server.start();
    try {
      await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '').pair(
          PairRequest(
        code: server.pairingCode,
        deviceId: 'attacker-2',
        deviceName: 'X',
        platform: 'android',
        appVersion: '1.1.0',
      ));
      fail('重启后不该放行：锁定状态必须持久化');
    } on ApiClientException catch (e) {
      expect(e.statusCode, 429);
    }
  });
}
