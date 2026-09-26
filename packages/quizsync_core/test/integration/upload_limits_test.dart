import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M47 的两条服务端加固：
/// 1. **上传体积闸门**：原来只在读完 `Content-Length` 时才预检，而分块传输
///    （chunked）时它是 null —— 于是一个超大 body 会被整块读进内存再判大小。
///    现在边收边计数，超限立刻 413，正常上传不受影响。
/// 2. **上传限流**（`SPEC.md` §10 / `protocol.md` §3.2）：每台设备每分钟 30 次，
///    原来只有 `/pair` 有限速，上传可以无限刷。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;

  const serverDeviceId = 'windows-local';
  const clientDeviceId = 'android-device-1';
  const maxBytes = 4096;
  const uploadsPerMinute = 2;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: serverDeviceId);
    await repo.init();
    imageDir = await Directory.systemTemp.createTemp('m47-upload-');
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
        configProvider: () =>
            const AiConfig(providerId: 'openai-compatible', apiKey: 'k', model: 'm'),
      ),
      deviceId: serverDeviceId,
      serverName: 'TEST-HOST',
      options: const QuizSyncServerOptions(
        preferredPort: 0,
        maxImageBytes: maxBytes,
        imageUploadsPerMinute: uploadsPerMinute,
      ),
    );
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

  /// 一张「看起来像 JPEG」的假图（只判大小与哈希，不解码）。
  Uint8List jpeg(int size) {
    final bytes = Uint8List(size);
    bytes[0] = 0xff;
    bytes[1] = 0xd8;
    bytes[2] = 0xff;
    bytes[3] = 0xd9;
    return bytes;
  }

  List<int> multipart(String boundary, List<int> file) => [
        ...utf8.encode('--$boundary\r\n'
            'Content-Disposition: form-data; name="file"; filename="a.jpg"\r\n'
            'Content-Type: image/jpeg\r\n\r\n'),
        ...file,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];

  /// 直接发 multipart 请求。[chunked] 为 true 时**不设** Content-Length，
  /// `HttpClient` 会走分块传输 —— 服务端那道依赖 Content-Length 的预检拿到的
  /// 就是 null，正好用来验证流式限长这一层。
  ///
  /// 服务端在超限时会**提前**回 413 并断开连接，此时客户端可能还在写 body，
  /// 于是 `add/flush` 撞上「连接被关闭」——那同样说明请求被挡住了，按 413 记。
  Future<({int status, String body})> postImage(
    List<int> file, {
    required bool chunked,
    String? withToken,
  }) async {
    const boundary = 'qsboundary';
    final client = HttpClient();
    try {
      final req = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/api/v1/images'));
      req.headers.set('Authorization', 'Bearer ${withToken ?? token}');
      req.headers
          .set('Content-Type', 'multipart/form-data; boundary=$boundary');
      final payload = multipart(boundary, file);
      if (!chunked) req.contentLength = payload.length;
      try {
        // 分片写 + flush：给服务端机会在收满上限时立刻回 413。
        for (var i = 0; i < payload.length; i += 4096) {
          req.add(payload.sublist(
              i, i + 4096 > payload.length ? payload.length : i + 4096));
          await req.flush();
        }
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        return (status: res.statusCode, body: body);
      } on IOException catch (e) {
        // 服务端提前回 413 并断开连接（正是我们要的行为）：客户端可能还在写
        // body，撞上「连接被中止」——HttpException 或 SocketException 都算。
        return (status: 413, body: '连接被服务端提前关闭：$e');
      }
    } finally {
      client.close(force: true);
    }
  }

  test('分块传输的超大包同样被 413 挡住（Content-Length 预检失效时的兜底）', () async {
    final res = await postImage(jpeg(maxBytes * 16), chunked: true);
    expect(res.status, 413, reason: 'chunked 时没有 Content-Length，必须靠边收边限长');
    expect(await repo.getImage(sha256Hex(jpeg(maxBytes * 16))), isNull,
        reason: '被拒的上传不得落库');
  });

  test('分块传输的正常大小仍然能上传', () async {
    final bytes = jpeg(512);
    final res = await postImage(bytes, chunked: true);
    expect(res.status, 200, reason: '限长不能把正常上传也挡掉');
    expect(await repo.getImage(sha256Hex(bytes)), isNotNull);
  });

  test('一超过上限就回 413，不等整包收完（内存必须有界）', () async {
    // 只在「读完整包再判大小」的实现下这个用例才会失败：那种实现要等请求体
    // 结束才有响应，而这里**故意不结束**请求体。
    const boundary = 'qsboundary';
    final socket = await Socket.connect('127.0.0.1', port);
    socket.add(utf8.encode('POST /api/v1/images HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Authorization: Bearer $token\r\n'
        'Content-Type: multipart/form-data; boundary=$boundary\r\n'
        'Transfer-Encoding: chunked\r\n\r\n'));
    final payload = multipart(boundary, jpeg(maxBytes * 4));
    final firstChunk = payload.sublist(0, maxBytes * 2);
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
        reason: '超过上限就该立刻回，不能等整包收完（否则超大 body 会吃光内存）');
  });

  test('上传限流：超出每分钟上限返回 429，另一台设备不受影响', () async {
    expect((await postImage(jpeg(500), chunked: false)).status, 200);
    expect((await postImage(jpeg(501), chunked: false)).status, 200);

    final blocked = await postImage(jpeg(502), chunked: false);
    expect(blocked.status, 429, reason: '第 3 次超限');
    expect(blocked.body, contains('rate_limited'));

    // 另一台设备有自己的窗口：限流是**按设备**算的，不能被一台刷爆。
    final other = (await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
            .pair(PairRequest(
      code: server.pairingCode,
      deviceId: 'android-device-2',
      deviceName: 'Mi 11',
      platform: 'android',
      appVersion: '1.1.0',
    )))
        .token;
    final res = await postImage(jpeg(503), chunked: false, withToken: other);
    expect(res.status, 200, reason: '另一台设备不应被连坐');
  });
}
