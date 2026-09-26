import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quizsync_server/quizsync_server_core.dart';
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/constants.dart';
import 'package:quizsync_server/src/engine.dart';
import 'package:quizsync_server/src/server.dart';
import 'package:quizsync_server/src/store.dart';
import 'package:quizsync_server/src/tasks.dart';
import 'package:quizsync_server/src/terminal.dart';
import 'package:test/test.dart';

import 'support.dart';

/// 一台**真** Server（真 HTTP + 真 WebSocket）+ 假 AI。
class Harness {
  final Directory temp;
  final ConfigPaths paths;
  final ServerStore store;
  final ScriptedProvider provider;
  final ServerTasks tasks;
  final QuizSyncServer server;
  final int port;
  final StringBuffer out;

  Harness._(this.temp, this.paths, this.store, this.provider, this.tasks,
      this.server, this.port, this.out);

  static Future<Harness> start({
    String aiText = kFixtureAiText,
    ServerOptions options = const ServerOptions(preferredPort: 0),
  }) async {
    final temp = Directory.systemTemp.createTempSync('quizsync-server-e2e');
    final paths = ConfigPaths(temp);
    final out = StringBuffer();
    final log = Terminal.buffer(out);
    final store = await ServerStore.open(paths);
    final provider = ScriptedProvider(aiText);
    final engine = RecognitionEngine(
      deviceId: store.deviceId,
      providerOf: (_) => provider,
    );
    late final ServerTasks tasks;
    late final QuizSyncServer server;
    tasks = ServerTasks(
      store: store,
      engine: engine,
      configProvider: () => const AiConfig(
        providerId: 'openai-compatible',
        baseUrl: 'https://example.invalid',
        apiKey: 'test-key',
        model: 'test-model',
      ),
      onUpdate: (taskId, status, sessionId, imageCount) => server
          .notifyTaskUpdate(taskId, status, sessionId, imageCount: imageCount),
      log: log,
    );
    server = QuizSyncServer(
      store: store,
      tasks: tasks,
      log: log,
      options: options,
      controlToken: 'probe-control-token',
    );
    final port = await server.start();
    return Harness._(temp, paths, store, provider, tasks, server, port, out);
  }

  Future<void> dispose() async {
    await server.stop();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }

  /// 走完整的配对流程，返回带 token 的客户端。
  Future<TestHttp> pair({
    String code = '',
    String name = 'Pixel 7',
    String deviceId = 'phone-1',
  }) async {
    final anon = TestHttp(port);
    final resp = await anon.postJson('/api/v1/pair', {
      'code': code.isEmpty ? server.pairingCode : code,
      'device_id': deviceId,
      'device_name': name,
      'platform': 'android',
      'app_version': '1.0.0',
    });
    expect(resp.status, anyOf(200, 409), reason: 'pair 失败：${resp.body}');
    return TestHttp(port, token: resp.body['token'] as String);
  }

  /// 一张能被识别的「截图」（内容随便，服务端不解码图片）。
  /// hash 必须与字节一致 —— 真实链路里 hash 就是对 JPEG 字节算出来的。
  PageInput page(int seed) {
    final bytes = Uint8List.fromList([seed, 1, 2, 3]);
    return PageInput(
      hash: sha256Hex(bytes),
      jpeg: bytes,
      width: 1600,
      height: 900,
    );
  }
}

void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.start();
  });

  tearDown(() async {
    await h.dispose();
  });

  test('GET /info 无需鉴权，字段与 Desktop 版同构', () async {
    final anon = TestHttp(h.port);
    final info = await anon.get('/api/v1/info');
    expect(info.status, 200);
    expect(info.body['protocol_version'], kProtocolVersion);
    expect(info.body['platform'], 'windows');
    expect(info.body['app_version'], kServerVersion);
    expect(info.body['ai_configured'], isTrue);
    expect(info.body['active_collection_id'], isNotEmpty);
    expect(info.body['active_collection_name'], kDefaultCollectionName);
    expect(info.body['capabilities'], contains('multipage'));
  });

  test('配对：错码 401 / 对码拿 token / 无 token 一律 401', () async {
    final anon = TestHttp(h.port);
    final wrong = await anon.postJson('/api/v1/pair', {
      'code': '000000',
      'device_id': 'phone-x',
      'device_name': 'X',
      'platform': 'android',
      'app_version': '1.0.0',
    });
    expect(wrong.status, 401);
    expect(wrong.body['code'], anyOf('invalid_code', 'rate_limited'));

    final client = await h.pair();
    expect((await client.get('/api/v1/collections')).status, 200);
    expect((await TestHttp(h.port).get('/api/v1/collections')).status, 401);
    expect((await TestHttp(h.port, token: 'deadbeef').get('/api/v1/info')).status,
        200, reason: '/info 是不需要鉴权的探测端点');
    expect(
        (await TestHttp(h.port, token: 'deadbeef').get('/api/v1/devices')).status,
        401);
  });

  test('WS：握手 hello + 本机截屏任务的 task_update / task_result', () async {
    final client = await h.pair();
    final ws = await TestSocket.connect(h.port, client.token!);
    final hello = await ws.waitFor('hello');
    expect(hello['server_device_id'], h.store.deviceId,
        reason: 'hello 必须报服务端自己的 device_id');
    expect(hello['active_collection_id'], h.store.collection.collectionId);

    // 本机热键路径：截图 → tasks.run（与 CaptureFlow 调的是同一个入口）。
    final outcome = await h.tasks.run(
      pages: [h.page(1)],
      sourceDevice: h.store.deviceId,
    );
    expect(outcome.ok, isTrue, reason: outcome.errorMessage);

    final update = await ws.waitFor('task_update');
    expect(update['status'], 'analyzing');
    expect(update['image_count'], 1);
    final result = await ws.waitFor('task_result');
    final session = Map<String, dynamic>.from(result['session'] as Map);
    expect(session['session_id'], outcome.sessionId);
    expect(session['source_device'], h.store.deviceId,
        reason: '安卓端靠 source_device 判断这不是本机自己发起的识别');
    expect(session['collection_id'], h.store.collection.collectionId);
    expect((session['questions'] as List), hasLength(2));
    expect(session['image_hashes'], hasLength(1));
    await ws.close();
  });

  test('GET /tasks/active：进行中报页数、完成带完整会话、idle 时也没有任务', () async {
    final client = await h.pair();
    final idle = await client.get('/api/v1/tasks/active');
    expect(idle.status, 200);
    expect(idle.body['status'], 'idle');
    expect(idle.body['collections'], hasLength(1));
    expect(idle.body['active_collection_name'], kDefaultCollectionName);

    final outcome =
        await h.tasks.run(pages: [h.page(2), h.page(3)], sourceDevice: h.store.deviceId);
    final done = await client.get('/api/v1/tasks/active');
    expect(done.body['status'], 'done');
    expect(done.body['session_id'], outcome.sessionId);
    expect(done.body['image_count'], 2);
    expect(done.body['updated_at'], greaterThan(0));
    final session = Map<String, dynamic>.from(done.body['session'] as Map);
    expect(session['image_count'], 2);
    expect((session['questions'] as List), hasLength(2));
  });

  test('手机提交的任务：POST /images → POST /tasks → WS 收到结果', () async {
    final client = await h.pair();
    final ws = await TestSocket.connect(h.port, client.token!);
    await ws.waitFor('hello');

    final up = await client.uploadImage(kJpegBytes);
    expect(up.status, 200);
    final hash = up.body['image_hash'] as String;
    expect(up.body['existed'], isFalse);
    expect(up.body['size'], kJpegBytes.length);
    // 重复上传按 hash 幂等。
    expect((await client.uploadImage(kJpegBytes)).body['existed'], isTrue);

    // 按需下载（安卓端补传原图用）。
    final anon = TestHttp(h.port);
    expect((await anon.get('/api/v1/images/$hash')).status, 401);
    final download = await client.getBytes('/api/v1/images/$hash');
    expect(download.status, 200);
    expect(download.bytes, kJpegBytes);

    final created = await client.postJson('/api/v1/tasks', {
      'task_id': 'task-phone-1',
      'image_hash': hash,
      'image_hashes': [hash],
      'source_device': 'phone-1',
      'created_at': nowMs(),
    });
    expect(created.status, 202);
    expect(created.body['status'], 'queued');
    final sessionId = created.body['session_id'] as String;

    final result = await ws.waitFor('task_result');
    final session = Map<String, dynamic>.from(result['session'] as Map);
    expect(session['session_id'], sessionId);
    expect(session['source_device'], 'phone-1');

    final got = await client.get('/api/v1/tasks/task-phone-1');
    expect(got.status, 200);
    expect(got.body['status'], 'done');
    expect(got.body['session_id'], sessionId);
    expect(Map<String, dynamic>.from(got.body['session'] as Map)['questions'],
        hasLength(2));
    await ws.close();
  });

  test('协议错误路径：缺字段 400 / 页数超限 400 / 没上传过的图 400', () async {
    final client = await h.pair();
    expect((await client.postJson('/api/v1/tasks', {'task_id': 't'})).status, 400);
    expect(
      (await client.postJson('/api/v1/tasks', {
        'task_id': 't2',
        'image_hash': 'nope',
        'image_hashes': List.generate(7, (i) => 'h$i'),
      })).body['code'],
      'too_many_pages',
    );
    expect(
      (await client.postJson('/api/v1/tasks', {
        'task_id': 't3',
        'image_hash': 'not-uploaded',
      })).body['code'],
      'invalid_request',
    );
    expect((await client.postJson('/api/v1/collections/other/select', {})).status,
        404);
  });

  test('同图复用：同一张图再识别一次不再花 AI（不重复调用 provider）', () async {
    final first = await h.tasks.run(pages: [h.page(9)], sourceDevice: h.store.deviceId);
    expect(first.ok, isTrue);
    expect(h.provider.calls, 1);

    final reusable = h.tasks.findReusable([h.page(9).hash]);
    expect(reusable, isNotNull);
    expect(reusable!.session.sessionId, first.sessionId);

    // 页序不同（多一页）不得命中复用。
    expect(h.tasks.findReusable([h.page(9).hash, h.page(10).hash]), isNull);
  });

  test('手机同图再提交：直接命中缓存，不再调 AI', () async {
    final client = await h.pair();
    final page = h.page(21);
    // 先在主机侧识别一次（等价于用户按了一次截图热键）。
    final first = await h.tasks.run(pages: [page], sourceDevice: h.store.deviceId);
    expect(h.provider.calls, 1);

    final again = await client.postJson('/api/v1/tasks', {
      'task_id': 'task-cached',
      'image_hash': page.hash,
      'image_hashes': [page.hash],
      'source_device': 'phone-1',
    });
    expect(again.status, 202);
    expect(again.body['cached'], isTrue);
    expect(again.body['status'], 'done');
    expect(again.body['session_id'], first.sessionId);
    expect(h.provider.calls, 1, reason: '命中缓存不得再调 AI');
  });

  test('「重新生成」起一个新会话并真的再调一次 AI', () async {
    final client = await h.pair();
    final first = await h.tasks.run(pages: [h.page(4)], sourceDevice: h.store.deviceId);
    expect(h.provider.calls, 1);

    final resp = await client.post('/api/v1/sessions/${first.sessionId}/reanalyze');
    expect(resp.status, 202);
    final newId = resp.body['session_id'] as String;
    expect(newId, isNot(first.sessionId));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(h.provider.calls, 2);
    expect(h.store.getSession(newId)!.questions, hasLength(2));
  });

  test('失败任务可重试（复用同一会话与 task_id）', () async {
    // 先让 provider 抛错，跑出一个失败会话。
    h.provider.failure = const AiException(AiErrorKind.auth, 'bad key');
    final failed = await h.tasks.run(pages: [h.page(5)], sourceDevice: h.store.deviceId);
    expect(failed.ok, isFalse);
    expect(failed.errorCode, 'ai_auth');
    expect(h.store.getSession(failed.sessionId)!.session.status, TaskState.failed);

    h.provider.failure = null;
    final client = await h.pair();
    final retry = await client.post('/api/v1/tasks/${failed.taskId}/retry');
    expect(retry.status, 200);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(h.store.getSession(failed.sessionId)!.session.status, TaskState.done);
  });

  test('AI 未配置时任务失败并给出 ai_auth（安卓端会显示「主机尚未配置 AI」）', () async {
    final store = h.store;
    final tasks = ServerTasks(
      store: store,
      engine: RecognitionEngine(deviceId: store.deviceId, providerOf: (_) => h.provider),
      configProvider: () => const AiConfig(),
      onUpdate: (_, _, _, _) {},
      log: Terminal.buffer(StringBuffer()),
    );
    final outcome = await tasks.run(pages: [h.page(11)], sourceDevice: store.deviceId);
    expect(outcome.ok, isFalse);
    expect(outcome.errorCode, 'ai_auth');
    expect(outcome.errorMessage, '主机尚未配置 AI');
  });

  test('同步端点：ops 恒为空、push 幂等计入 applied、snapshot 结构完整', () async {
    final client = await h.pair();
    final pull = await client.get('/api/v1/sync/ops?from_device=${h.store.deviceId}&since_lamport=0');
    expect(pull.status, 200);
    expect(pull.body['ops'], isEmpty);
    expect(pull.body['has_more'], isFalse);
    expect((await client.get('/api/v1/sync/ops')).status, 400, reason: '缺 from_device');

    final op = {
      'op_id': 'op-1',
      'device_id': 'phone-1',
      'lamport': 1,
      'entity': 'question',
      'entity_id': 'q1',
      'op_type': 'upsert',
      'fields_json': {'stem': 'x'},
      'created_at': 1,
    };
    expect((await client.postJson('/api/v1/sync/ops', {'ops': [op]})).body['applied'], 1);
    expect((await client.postJson('/api/v1/sync/ops', {'ops': [op]})).body['applied'], 0);

    final snapshot = await client.get('/api/v1/sync/snapshot');
    expect(snapshot.status, 200);
    expect(snapshot.body['collections'], hasLength(1));
    expect(snapshot.body['devices'], hasLength(1));
    expect(snapshot.body['watermark'], 0);
  });

  test('合集：只有一个默认合集，切换它成功、别的 404', () async {
    final client = await h.pair();
    final list = await client.get('/api/v1/collections');
    expect(list.body['collections'], hasLength(1));
    final id = list.body['active_collection_id'] as String;
    expect(id, h.store.collection.collectionId);
    expect((await client.post('/api/v1/collections/$id/select')).status, 200);
    expect((await client.post('/api/v1/collections/nope/select')).status, 404);
  });

  test('吊销设备：HTTP 401 revoked + WS 收到 device_revoked', () async {
    final client = await h.pair();
    final ws = await TestSocket.connect(h.port, client.token!);
    await ws.waitFor('hello');

    final resp = await client.delete('/api/v1/devices/phone-1');
    expect(resp.status, 200);
    expect((await ws.waitFor('device_revoked'))['device_id'], 'phone-1');

    final after = await client.get('/api/v1/collections');
    expect(after.status, 401);
    expect(after.body['code'], 'revoked');
    await ws.close();
  });

  test('服务端关闭后端口释放（不留监听）', () async {
    final harness = await Harness.start();
    final port = harness.port;
    await harness.dispose();
    // 立刻重绑同一端口必须成功（说明 stop() 真的把 listener 关掉了）。
    final again = await HttpServer.bind(InternetAddress.anyIPv4, port);
    await again.close(force: true);
  });

  test('停机接口：只有回环地址 + 正确控制令牌才能停（--stop 走的就是它）', () async {
    var stopped = 0;
    h.server.onShutdownRequested = () => stopped++;
    final anon = TestHttp(h.port);

    // 没有令牌 / 令牌错误：一律 403，而且不触发停机。
    expect((await anon.post('/api/v1/shutdown')).status, 403);
    expect(
        (await anon.post('/api/v1/shutdown',
                extraHeaders: {'X-QS-Control': 'wrong'}))
            .status,
        403);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(stopped, 0);

    // 正确令牌（本机回环）：200，并在响应之后触发优雅停机回调。
    final ok = await anon.post('/api/v1/shutdown',
        extraHeaders: {'X-QS-Control': h.server.controlToken});
    expect(ok.status, 200);
    expect(ok.body['stopping'], isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(stopped, 1);
  });

  test('停机接口不参与 Bearer 鉴权（是本机开关，不是协议的一部分）', () async {
    // 带着一个乱七八糟的 Bearer 也必须能走令牌这条路（否则 --stop 会被 401 挡掉）。
    final resp = await TestHttp(h.port, token: 'not-a-real-token')
        .post('/api/v1/shutdown',
            extraHeaders: {'X-QS-Control': h.server.controlToken});
    expect(resp.status, 200);
  });

  test('端口被占用时自动往后探测', () async {
    final blocker = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final occupied = blocker.port;
    final temp = Directory.systemTemp.createTempSync('quizsync-server-port');
    final store = await ServerStore.open(ConfigPaths(temp));
    final log = Terminal.buffer(StringBuffer());
    final server = QuizSyncServer(
      store: store,
      tasks: ServerTasks(
        store: store,
        engine: RecognitionEngine(deviceId: store.deviceId, providerOf: (_) => h.provider),
        configProvider: () => const AiConfig(),
        onUpdate: (_, _, _, _) {},
        log: log,
      ),
      log: log,
      options: ServerOptions(preferredPort: occupied),
    );
    final bound = await server.start();
    expect(bound, isNot(occupied));
    await server.stop();
    await blocker.close(force: true);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('CLI 面板渲染用的是真实运行状态', () async {
    await h.pair();
    expect(h.out.toString(), isNot(contains('NaN')));
  });

  test('日志行都是中文标签 + 一句中文说明', () async {
    final client = await h.pair();
    final ws = await TestSocket.connect(h.port, client.token!);
    await ws.waitFor('hello');
    await h.tasks.run(pages: [h.page(7)], sourceDevice: h.store.deviceId);
    final text = h.out.toString();
    expect(text, contains('[手机] 配对成功：Pixel 7（android）'));
    expect(text, contains('[手机] 已连接：Pixel 7'));
    expect(text, contains('[同步] 识别结果已推送给手机'));
    await ws.close();
  });

  // ------------------------------------------------------------
  // M47：与 Desktop 版对齐的四条服务端加固
  // ------------------------------------------------------------

  test('M47：分块传输的超大包也会被 413 挡住，且一超限就回（不等整包收完）', () async {
    final client = await h.pair();
    const boundary = 'qsboundary';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="a.jpg"\r\n'
        'Content-Type: image/jpeg\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final body = <int>[...head, ...Uint8List(kMaxImageBytes + 4096), ...tail];

    // 裸 socket + 分块传输：**不设** Content-Length，而且发完超过上限的一段之后
    // 故意不结束请求体 —— 只有「边收边限长」的实现才会在这时候回 413。
    final socket = await Socket.connect('127.0.0.1', h.port);
    socket.add(utf8.encode('POST /api/v1/images HTTP/1.1\r\n'
        'Host: 127.0.0.1:${h.port}\r\n'
        'Authorization: Bearer ${client.token}\r\n'
        'X-QS-Client-Version: 1.0.0\r\n'
        'Content-Type: multipart/form-data; boundary=$boundary\r\n'
        'Transfer-Encoding: chunked\r\n\r\n'));
    final firstChunk = body.sublist(0, kMaxImageBytes + 2048);
    socket.add(utf8.encode('${firstChunk.length.toRadixString(16)}\r\n'));
    socket.add(firstChunk);
    socket.add(utf8.encode('\r\n'));
    await socket.flush();

    final received = <int>[];
    final sub = socket.listen(received.addAll);
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();
    socket.destroy();

    final text = utf8.decode(received, allowMalformed: true);
    expect(text, contains('413'),
        reason: 'chunked 时没有 Content-Length，必须靠边收边限长（旧实现会一直等到整包收完）');
  });

  test('M47：上传限流按设备算（第 3 次 429，另一台设备不受影响）', () async {
    final limited = await Harness.start(
        options: const ServerOptions(
            preferredPort: 0, imageUploadsPerMinute: 2));
    try {
      final a = await limited.pair();
      expect((await a.uploadImage(kJpegBytes)).status, 200);
      expect((await a.uploadImage(kJpegBytes)).status, 200);
      final blocked = await a.uploadImage(kJpegBytes);
      expect(blocked.status, 429, reason: '第 3 次超限');
      expect(blocked.body['code'], 'rate_limited');

      final b = await limited.pair(deviceId: 'phone-2', name: 'Mi 11');
      expect((await b.uploadImage(kJpegBytes)).status, 200,
          reason: '滑窗是按设备的，另一台不该被连坐');
    } finally {
      await limited.dispose();
    }
  });

  test('M47：snapshot 按会话分页（limit / offset / has_more）', () async {
    final client = await h.pair();
    for (var i = 0; i < 3; i++) {
      h.store.sessions['s$i'] = StoredSession(
        session: Session(
          sessionId: 's$i',
          imageHash: 'h$i',
          sourceDevice: h.store.deviceId,
          status: TaskState.done,
          questionCount: 0,
          createdAt: 1000 + i,
          updatedAt: 1000 + i,
          updatedBy: h.store.deviceId,
        ),
        questions: const [],
        imageHashes: ['h$i'],
      );
    }

    List<String> idsOf(Map<String, dynamic> body) => [
          for (final s in body['sessions'] as List)
            (s as Map)['session_id'].toString()
        ];

    final first = await client.get('/api/v1/sync/snapshot?limit=2');
    expect(first.status, 200);
    expect(idsOf(first.body), hasLength(2));
    expect(first.body['has_more'], isTrue);
    expect(first.body['next_offset'], 2);

    final rest = await client
        .get('/api/v1/sync/snapshot?limit=2&offset=${first.body['next_offset']}');
    expect(idsOf(rest.body), hasLength(1), reason: '第二页只剩一条');
    expect(rest.body['has_more'], isFalse);
    expect({...idsOf(first.body), ...idsOf(rest.body)}, {'s0', 's1', 's2'},
        reason: '两页合起来正好是全量（不重不漏）');
  });

  test('M47：已有识别在进行时，新建任务回 429（没有队列就不假装排队）', () async {
    final client = await h.pair();
    h.provider.delay = const Duration(milliseconds: 400);
    final uploaded = await client.uploadImage(kJpegBytes);
    final hash = uploaded.body['image_hash'] as String;

    final first = await client.postJson('/api/v1/tasks', {
      'task_id': 't-1',
      'image_hash': hash,
      'source_device': 'phone-1',
    });
    expect(first.status, 202);

    final second = await client.postJson('/api/v1/tasks', {
      'task_id': 't-2',
      'image_hash': hash,
      'source_device': 'phone-1',
    });
    expect(second.status, 429);
    expect(second.body['code'], 'queue_full');

    // 等第一条真的跑完再拆环境（否则临时目录会在它写盘中途被删）。
    await Future<void>.delayed(const Duration(milliseconds: 700));
  });
}
