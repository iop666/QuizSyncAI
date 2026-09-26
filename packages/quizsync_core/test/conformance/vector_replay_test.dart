@Tags(['conformance'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 语言无关一致性向量的 **Dart 参考回放器**。
///
/// 向量在 `QuizSyncProtocol/conformance/vectors/*.ndjson`（格式见该仓库
/// `conformance/README.md`）。这个回放器是 v1 快照的裁判：它必须 100% 通过 ——
/// 红一条就说明快照或向量写错了。
///
/// **纪律**：只做 I/O 适配。用 `dart:io` 的 HttpClient 打真实 HTTP，**不引用
/// `ApiClient` / 服务端内部类**（拿被裁判的实现去断言，就不是裁判了），断言值
/// 全部来自向量文件。
///
/// 向量目录：环境变量 `QS_VECTORS`，默认 `../../QuizSyncProtocol/conformance/vectors`
/// （相对 `packages/quizsync_core`）。目录不存在 = **失败**，不允许静默跳过。
void main() {
  final configured = Platform.environment['QS_VECTORS'] ??
      '../../../QuizSyncProtocol/conformance/vectors';
  final dir = Directory(configured);
  if (!dir.existsSync()) {
    test('一致性向量目录必须存在（不接受静默跳过）', () {
      fail('找不到向量目录：${dir.absolute.path}\n'
          '请设置 QS_VECTORS 指向 QuizSyncProtocol/conformance/vectors');
    });
    return;
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ndjson'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    test('一致性向量目录不能是空的', () => fail('${dir.absolute.path} 里没有 *.ndjson'));
    return;
  }

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('回放 $name', () async {
      final harness = await _Harness.start();
      try {
        await harness.run(_loadSteps(file));
      } finally {
        await harness.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 180)));
  }
}

List<Map<String, dynamic>> _loadSteps(File file) {
  final out = <Map<String, dynamic>>[];
  final lines = const Utf8Decoder().convert(file.readAsBytesSync()).split('\n');
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) continue;
    final Map<String, dynamic> step;
    try {
      step = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      throw StateError('$file 第 ${i + 1} 行不是合法 JSON：$e');
    }
    final expected = out.length + 1;
    if (step['step'] != expected) {
      throw StateError(
          '$file 第 ${i + 1} 行的 step=${step['step']}，应为 $expected（步骤必须连续）');
    }
    out.add(step);
  }
  return out;
}

/// 一台干净服务端 + 一个可控时钟 + 变量表。
class _Harness {
  _Harness._(this.serverDb, this.repo, this.server, this.imageDir, this.port,
      this.clock);

  final QuizSyncDb serverDb;
  final CoreRepository repo;
  final QuizSyncServer server;
  final Directory imageDir;

  /// 服务端实际监听的端口（`start()` 之后才知道）。
  int port;

  /// 注入给服务端的假时钟（`QuizSyncServer` 的 `now`）—— **必须是同一个实例**，
  /// 否则 `clock` 步骤推进的是另一个时钟，服务端那边时间纹丝不动。
  final _Clock clock;

  int get fakeNow => clock.now;
  set fakeNow(int v) => clock.now = v;

  final Map<String, String> vars = {};
  final HttpClient _client = HttpClient();

  /// 当前 WS 连接与它的收件箱（见 `_runWs`）。
  WebSocket? _ws;
  final List<Map<String, dynamic>> _wsInbox = [];
  bool _wsClosed = false;

  static Future<_Harness> start() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = QuizSyncDb(NativeDatabase.memory());
    final repo = CoreRepository(db: db, deviceId: 'server-device-1');
    await repo.init();
    final imageDir = await Directory.systemTemp.createTemp('qs-vectors-');
    final provider = FakeAiProvider(
        File('test/fixtures/single_choice.json').absolute.path);
    final engine = AnalysisEngine(
      provider: provider,
      cache: AnalysisCache(repo),
      quota: QuotaGuard(db),
      deviceId: 'server-device-1',
      retry: const RetryPolicy(sleeper: _noSleep),
    );
    final executor = ServerTaskExecutor(
      repo: repo,
      engine: engine,
      imageStore: DirectoryImageStore(imageDir.path),
      configProvider: () =>
          const AiConfig(apiKey: 'test-key', model: 'test-model'),
    );
    final clock = _Clock();
    final server = QuizSyncServer(
      repo: repo,
      imageStore: DirectoryImageStore(imageDir.path),
      executor: executor,
      deviceId: 'server-device-1',
      serverName: 'TEST-HOST',
      options: const QuizSyncServerOptions(preferredPort: 0),
      now: () => clock.now,
    );
    final harness = _Harness._(db, repo, server, imageDir, 0, clock);
    harness.port = await server.start();
    return harness;
  }

  Future<void> dispose() async {
    await _ws?.close();
    await server.stop();
    await serverDb.close();
    try {
      await imageDir.delete(recursive: true);
    } catch (_) {}
    _client.close(force: true);
  }

  String _var(String name) {
    if (name == 'pairingCode') return server.pairingCode;
    if (name == 'port') return '$port';
    final v = vars[name];
    if (v == null) throw StateError('变量 \$$name 还没有值（需要先 capture）');
    return v;
  }

  /// 把 `{"code": "$pairingCode"}` 这类占位符替换成实际值。
  Object? resolve(Object? node) {
    if (node is String) {
      return node.replaceAllMapped(
          RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)'), (m) => _var(m[1]!));
    }
    if (node is List) return node.map(resolve).toList();
    if (node is Map) {
      return node.map((k, v) => MapEntry(k.toString(), resolve(v)));
    }
    return node;
  }

  Future<void> run(List<Map<String, dynamic>> steps) async {
    for (final step in steps) {
      final where = 'step ${step['step']}（${step['title'] ?? ''}）';
      final action = step['do'];
      if (action is! Map) throw StateError('$where 缺少 do');
      final a = Map<String, dynamic>.from(action);
      if (a.containsKey('http')) {
        final spec = Map<String, dynamic>.from(a['http'] as Map);
        // `repeat: N` = 同一请求连发 N 次（每次都按 expect 断言），
        // 用来表达限流一类「同一个动作来很多次」的向量。
        final times = (spec.remove('repeat') as num?)?.toInt() ?? 1;
        for (var i = 0; i < times; i++) {
          await _runHttp(where, spec, step['expect'] as Map?);
        }
      } else if (a.containsKey('clock')) {
        final ms = (Map<String, dynamic>.from(a['clock'] as Map)['advance_ms']
                as num)
            .toInt();
        fakeNow += ms;
      } else if (a.containsKey('server')) {
        final s = Map<String, dynamic>.from(a['server'] as Map);
        if (s['refresh_pairing_code'] == true) server.refreshPairingCode();
        // 桌面端切合集后的那个广播入口（真实产品 API，不是测试专用钩子）。
        if (s['collection_changed'] == true) await server.notifyCollectionChanged();
      } else if (a.containsKey('seed')) {
        await _runSeed(where, Map<String, dynamic>.from(a['seed'] as Map));
      } else if (a.containsKey('poll')) {
        await _runPoll(where, Map<String, dynamic>.from(a['poll'] as Map),
            step['expect'] as Map?);
      } else if (a.containsKey('ws')) {
        await _runWs(where, Map<String, dynamic>.from(a['ws'] as Map));
      } else {
        // 未实现的操作 = 失败（宁可红着，也不要假的绿）。
        throw StateError('$where 用了回放器还没实现的操作：${a.keys.join(',')}');
      }
    }
  }

  /// 回放器侧的初始状态（服务端库里的合集 / 当前选中合集 / 已排队任务）。
  Future<void> _runSeed(String where, Map<String, dynamic> s) async {
    final col = s['collection'];
    if (col is Map) {
      final m = Map<String, dynamic>.from(col);
      await repo.upsertCollection(Collection(
        collectionId: m['id'].toString(),
        name: (m['name'] ?? '').toString(),
        createdAt: fakeNow,
        updatedAt: fakeNow,
        updatedBy: 'server-device-1',
      ));
    }
    final active = s['active_collection'];
    if (active is String) {
      await repo.setSetting(kActiveCollectionKey, resolve(active).toString());
    }
    final queued = s['queued_tasks'];
    if (queued is num) {
      for (var i = 0; i < queued.toInt(); i++) {
        await repo.db.into(repo.db.tasks).insert(TasksCompanion(
              taskId: Value('seed-task-$i'),
              imageHash: Value('seed-hash-$i'),
              sourceDevice: const Value('seed'),
              status: const Value('queued'),
              createdAt: Value(fakeNow),
            ));
      }
    }
    if (s.isNotEmpty &&
        !s.containsKey('collection') &&
        !s.containsKey('active_collection') &&
        !s.containsKey('queued_tasks')) {
      throw StateError('$where 用了回放器还不认识的 seed：${s.keys.join(',')}');
    }
  }

  /// WS 操作。**收件箱语义**：不为每条消息写一步，而是把到达的消息都收进箱子里，
  /// `expect` 从箱子里找**第一条匹配**的（并丢掉它之前的消息）—— 这样顺序仍然被钉住，
  /// 又不用把 `hello`/`task_update` 的每一个中间态都写进向量。
  Future<void> _runWs(String where, Map<String, dynamic> spec) async {
    if (spec.containsKey('connect')) {
      final auth = spec['connect'].toString();
      final token = auth == 'device' ? _var('token') : _var(auth.substring(7));
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$port/ws',
        headers: {'Authorization': 'Bearer $token'},
      );
      _ws = socket;
      _wsClosed = false;
      socket.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map) {
              _wsInbox.add(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {
            // 非 JSON 帧：本协议不发，收到就记一条便于排查。
            _wsInbox.add({'type': '<non-json>', 'raw': data.toString()});
          }
        },
        onDone: () => _wsClosed = true,
        onError: (_) => _wsClosed = true,
      );
      return;
    }

    if (spec.containsKey('send')) {
      final socket = _ws;
      if (socket == null) throw StateError('$where 还没连接就 send');
      socket.add(jsonEncode(resolve(spec['send'])));
      // dart:io 的 WebSocket 没有 flush：给事件循环一次机会把帧发出去。
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return;
    }

    if (spec['close'] == true) {
      await _ws?.close();
      _ws = null;
      return;
    }

    if (spec.containsKey('expect')) {
      final expected = spec['expect'];
      final maxMs = (spec['max_ms'] as num?)?.toInt() ?? 5000;
      final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
      while (DateTime.now().isBefore(deadline)) {
        for (var i = 0; i < _wsInbox.length; i++) {
          try {
            _match(resolve(expected), _wsInbox[i], '$where ws.expect',
                strictArrays: true);
            // 命中：丢掉它以及它之前的消息（顺序仍然被钉住）。
            _wsInbox.removeRange(0, i + 1);
            return;
          } catch (_) {
            // 不是这条：继续往后找。
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      throw StateError('$where ${maxMs}ms 内没等到期望的 WS 消息：'
          '期望 $expected，收到的 ${_wsInbox.length} 条是 $_wsInbox');
    }

    if (spec.containsKey('expect_none')) {
      // 负向断言：窗口内**不许**出现匹配的消息（例：服务端从发 `ops`）。
      final maxMs = (spec['max_ms'] as num?)?.toInt() ?? 400;
      final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
      while (DateTime.now().isBefore(deadline)) {
        for (final message in _wsInbox) {
          try {
            _match(resolve(spec['expect_none']), message, '$where ws.expect_none',
                strictArrays: true);
            throw StateError('$where 出现了不该出现的 WS 消息：$message');
          } catch (e) {
            if (e is StateError && e.message.startsWith('$where 出现了')) rethrow;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return;
    }

    if (spec['expect_closed'] == true) {
      final maxMs = (spec['max_ms'] as num?)?.toInt() ?? 3000;
      final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
      while (DateTime.now().isBefore(deadline)) {
        if (_wsClosed) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      throw StateError('$where 期望服务端关闭连接，但 $maxMs ms 内还活着');
    }

    throw StateError('$where 用了回放器不认识的 ws 操作：${spec.keys.join(',')}');
  }

  /// 轮询一个只读端点直到 `until` 里的 JSON 局部匹配成立（或超时）。
  ///
  /// 用于「任务从 queued 走到 done」这类异步收敛：向量只需要写清**等到什么**
  /// 与**最终期望什么**，不用关心要等几轮。
  Future<void> _runPoll(
      String where, Map<String, dynamic> spec, Map? expect) async {
    final until = spec['until'];
    final maxMs = (spec['max_ms'] as num?)?.toInt() ?? 15000;
    final intervalMs = (spec['interval_ms'] as num?)?.toInt() ?? 200;
    final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
    final httpSpec = Map<String, dynamic>.from(spec)
      ..remove('until')
      ..remove('max_ms')
      ..remove('interval_ms');
    _Resp? last;
    while (DateTime.now().isBefore(deadline)) {
      final got = await _httpOnce(where, httpSpec);
      last = got;
      if (until is Map) {
        try {
          _match(until, got.body, '$where until', strictArrays: true);
          break;
        } catch (_) {
          // 还没到目标状态：继续等。
        }
      } else {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
    if (last == null) fail('$where 轮询一次都没成功');
    if (until is Map) {
      try {
        _match(until, last.body, '$where until（${maxMs}ms 内）',
            strictArrays: true);
      } catch (e) {
        fail('$where 轮询超时：$e');
      }
    }
    _assert(where, expect, last);
  }

  Future<void> _runHttp(
      String where, Map<String, dynamic> spec, Map? expect) async {
    final got = await _httpOnce(where, spec);
    _assert(where, expect, got);
  }

  /// 发一次请求并返回响应（不做断言）。
  Future<_Resp> _httpOnce(String where, Map<String, dynamic> spec) async {
    final method = spec['method'].toString();
    final path =
        resolve(spec['path']).toString().replaceAll('\$port', '$port');
    final req = await _client
        .openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));

    final auth = spec['auth']?.toString() ?? 'none';
    switch (auth) {
      case 'none':
        break;
      case 'bogus':
        req.headers.set('Authorization', 'Bearer ${'0' * 64}');
        break;
      case 'empty':
        // 形如 `Authorization: Bearer `（令牌为空）
        req.headers.set('Authorization', 'Bearer ');
        break;
      case 'malformed':
        // 没有 Bearer 前缀
        req.headers.set('Authorization', 'Token abc');
        break;
      case 'device':
        req.headers.set('Authorization', 'Bearer ${_var('token')}');
        break;
      default:
        if (!auth.startsWith('device:')) {
          throw StateError('$where 的 auth 取值不认识：$auth');
        }
        req.headers
            .set('Authorization', 'Bearer ${_var(auth.substring(7))}');
    }
    final headers = spec['headers'];
    if (headers is Map) {
      headers.forEach((k, v) => req.headers.set(k.toString(), resolve(v).toString()));
    }

    final multipart = spec['multipart'];
    if (multipart is Map) {
      final m = Map<String, dynamic>.from(multipart);
      final bytes = (m['bytes'] as num).toInt();
      final field = m['field']?.toString() ?? 'file';
      final filename = m['filename']?.toString() ?? 'x.jpg';
      final boundary = '----qsVectorBoundary${DateTime.now().microsecondsSinceEpoch}';
      req.headers.contentType = ContentType('multipart', 'form-data',
          parameters: {'boundary': boundary});
      final head = utf8.encode('--$boundary\r\n'
          'Content-Disposition: form-data; name="$field"; filename="$filename"\r\n'
          'Content-Type: image/jpeg\r\n\r\n');
      final tail = utf8.encode('\r\n--$boundary--\r\n');
      final payload = <int>[...head, ...List<int>.filled(bytes, 0x41), ...tail];
      req.contentLength = payload.length;
      req.add(payload);
    } else if (spec['json'] != null) {
      final body = jsonEncode(resolve(spec['json']));
      req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
    } else if (spec['raw'] != null) {
      // 原样字节（用来测「body 不是合法 JSON」这类用例）。
      final bytes = utf8.encode(resolve(spec['raw']).toString());
      final ct = spec['content_type']?.toString() ?? 'application/json';
      req.headers.set('Content-Type', ct);
      req.contentLength = bytes.length;
      req.add(bytes);
    }

    final HttpClientResponse resp;
    try {
      resp = await req.close();
    } on HttpException catch (e) {
      // 服务端在客户端还在发的时候关连接（Windows 会发 RST）也走这里 ——
      // 报出是哪一步，别让排查从「Connection closed」开始猜。
      fail('$where 请求失败：$e');
    }
    final raw = <int>[];
    try {
      await for (final chunk in resp) {
        raw.addAll(chunk);
      }
    } on HttpException catch (e) {
      fail('$where 读响应体失败：$e');
    }
    final text = utf8.decode(raw, allowMalformed: true);
    Map<String, dynamic>? body;
    if (text.trim().isNotEmpty) {
      try {
        body = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {
        body = null;
      }
    }
    return (status: resp.statusCode, body: body, raw: raw, text: text);
  }

  /// 断言一个响应（`where` 用于失败信息）。
  void _assert(String where, Map? expect, _Resp got) {
    if (expect == null) return;
    final e = Map<String, dynamic>.from(expect);
    final body = got.body;
    if (e['status'] != null && got.status != (e['status'] as num).toInt()) {
      fail('$where 期望 HTTP ${e['status']}，实际 ${got.status}：${got.text}');
    }
    final bodyHash = e['body_sha256'];
    if (bodyHash != null) {
      final expected = resolve(bodyHash).toString();
      final actual = sha256Hex(Uint8List.fromList(got.raw));
      if (actual != expected) {
        fail('$where body_sha256 期望 $expected，实际 $actual');
      }
    }
    if (e['json'] != null && body == null) {
      fail('$where 期望 JSON 响应，实际：${got.text}');
    }
    if (e['json'] != null) {
      // 期望值里也允许写 `$变量`（capture 出来的 token / session_id / hash）。
      _match(resolve(e['json']), body, '$where json', strictArrays: true);
    }
    if (e['json_contains'] != null) {
      _match(resolve(e['json_contains']), body, '$where json_contains',
          strictArrays: false);
    }
    final regex = e['json_regex'];
    if (regex is Map) {
      regex.forEach((k, v) {
        final actual = _path(body, k.toString());
        final re = RegExp(resolve(v).toString());
        if (actual == null || !re.hasMatch(actual.toString())) {
          fail('$where json_regex[$k] 期望匹配 ${resolve(v)}，实际 $actual');
        }
      });
    }
    final capture = e['capture'];
    if (capture is Map) {
      capture.forEach((k, v) {
        final value = _path(body, v.toString());
        if (value == null) fail('$where capture[$k] 取不到路径 $v');
        vars[k.toString()] = value is String ? value : jsonEncode(value);
      });
    }
    // 断言某几个 JSON 路径**不存在**（安全类用例：响应里绝不能出现令牌哈希）。
    final absent = e['json_absent'];
    if (absent is List) {
      for (final p in absent) {
        final v = _path(body, p.toString());
        if (v != null) fail('$where json_absent：$p 不该出现，实际是 $v');
      }
    }
  }

  void _match(Object? expected, Object? actual, String where,
      {required bool strictArrays}) {
    if (expected is Map) {
      if (actual is! Map) fail('$where：期望对象，实际 $actual');
      expected.forEach((k, v) => _match(v, actual[k], '$where.$k',
          strictArrays: strictArrays));
      return;
    }
    if (expected is List) {
      if (actual is! List) fail('$where：期望数组，实际 $actual');
      if (strictArrays) {
        if (expected.length != actual.length) {
          fail('$where：期望 ${expected.length} 项，实际 ${actual.length} 项（$actual）');
        }
        for (var i = 0; i < expected.length; i++) {
          _match(expected[i], actual[i], '$where[$i]',
              strictArrays: strictArrays);
        }
      } else {
        for (final item in expected) {
          final ok = actual.any((candidate) {
            try {
              _match(item, candidate, where, strictArrays: true);
              return true;
            } catch (_) {
              return false;
            }
          });
          if (!ok) fail('$where：实际数组里找不到期望项 $item（实际 $actual）');
        }
      }
      return;
    }
    if (expected != actual) fail('$where：期望 $expected，实际 $actual');
  }

  Object? _path(Object? root, String path) {
    var node = root;
    final p = path.startsWith('\$.') ? path.substring(2) : path;
    for (final rawSeg in p.split('.')) {
      if (rawSeg.isEmpty) continue;
      // 支持 `name` 与 `name[2]` 两种段（数组下标）。
      final m = RegExp(r'^([^\[]*)((?:\[\d+\])*)$').firstMatch(rawSeg);
      if (m == null) return null;
      final name = m.group(1)!;
      if (name.isNotEmpty) {
        if (node is! Map) return null;
        node = node[name];
      }
      for (final idx in RegExp(r'\[(\d+)\]')
          .allMatches(m.group(2)!)
          .map((x) => int.parse(x.group(1)!))) {
        if (node is! List || idx >= node.length) return null;
        node = node[idx];
      }
    }
    return node;
  }
}

Future<void> _noSleep(Duration d) async {}

/// 假时钟（回放器的 `clock` 步骤推进它，服务端通过 `now` 注入读到它）。
class _Clock {
  int now = 1700000000000;
}

/// 一次 HTTP 响应的回放器视图。
typedef _Resp = ({
  int status,
  Map<String, dynamic>? body,
  List<int> raw,
  String text,
});
