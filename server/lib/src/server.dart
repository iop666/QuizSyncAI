import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../quizsync_server_core.dart';
import 'constants.dart';
import 'engine.dart' show AiConfigReadiness;
import 'store.dart';
import 'tasks.dart';
import 'terminal.dart';

/// 服务端可调参数（默认值与 Desktop 版一致，保证 Android 端体验不变）。
class ServerOptions {
  final int preferredPort;
  final int portRange;
  final int protocolVersion;
  final String appVersion;
  final Duration pairingTtl;
  final int pairAttemptsPerMinute;
  final int pairFailureLockThreshold;
  final Duration pairLockout;
  final int maxImageBytes;

  /// 上传接口限流：每台设备每分钟最多多少次（`SPEC.md` §10 / `protocol.md` §3.2）。
  /// ≤ 0 表示不限流（供单测批量上传用）。M47 与 Desktop 版对齐。
  final int imageUploadsPerMinute;

  const ServerOptions({
    this.preferredPort = kDefaultPort,
    this.portRange = kPortRange,
    this.protocolVersion = kProtocolVersion,
    this.appVersion = kServerVersion,
    this.pairingTtl = const Duration(minutes: 5),
    this.pairAttemptsPerMinute = 5,
    this.pairFailureLockThreshold = 10,
    this.pairLockout = const Duration(seconds: 60),
    this.maxImageBytes = kMaxImageBytes,
    this.imageUploadsPerMinute = 30,
  });
}

enum AuthStatus { missing, invalid, valid, revoked }

class _PairFailure implements Exception {
  final int status;
  final String code;
  final String message;
  final int? retryAfterSeconds;

  _PairFailure(this.status, this.code, this.message, [this.retryAfterSeconds]);
}

/// QuizSyncAI Server 的局域网服务端：**protocol.md 的全部端点 + `/ws`**，
/// 与 Desktop 版实现的是同一份协议，Android 分不出自己连的是哪一个。
///
/// 存储换成 Server 自己的 [ServerStore]（JSON + 图片目录，不用数据库），
/// 任务链路换成 [ServerTasks]（无队列、无缓存表）。
class QuizSyncServer {
  final ServerStore store;
  final ServerTasks tasks;
  final Terminal log;
  final ServerOptions options;
  final int Function() now;

  /// 状态变化（设备上下线、配对码刷新）时回调，CLI 用来重画面板。
  void Function()? onStateChanged;

  /// 手机连上 / 断开时的日志出口（CLI 打印 `[Mobile] Device connected`）。
  void Function(String deviceId, String name)? onDeviceConnected;
  void Function(String deviceId, String name)? onDeviceDisconnected;

  /// `POST /api/v1/shutdown` 的控制令牌（无窗口后台模式用 `--stop` 优雅退出）。
  ///
  /// 它只写在本机的运行文件（`runtime.json`）里，而且这个接口**只接受回环地址**，
  /// 所以手机端既拿不到也用不了 —— 不是协议的一部分，纯本机停机开关。
  final String controlToken;

  /// 收到合法停机请求时回调（CLI 接到就优雅退出）。
  void Function()? onShutdownRequested;

  /// 本机命令行转发（`POST /api/v1/console`）：无窗口后台运行之后，用户重新双击
  /// exe 得到的是一个「前端窗口」，他敲的每条命令都送到**这个正在跑的实例**上执行，
  /// 输出原样回给那个窗口。回调由 CLI 提供（就是窗口内命令处理器）。
  Future<String> Function(String command)? onConsoleCommand;

  HttpServer? _httpServer;
  int? _port;

  // 配对状态。
  String _pairingCode = generatePairingCode();
  late int _pairingExpiresAt;

  // 限速窗口。
  final List<int> _pairAttemptTimestamps = [];
  int _pairFailures = 0;
  int _lockedUntil = 0;

  /// 上传接口的滑窗（每台设备各自一份，M47 与 Desktop 版对齐）。
  final Map<String, List<int>> _uploadTimestamps = {};

  // WS 连接表：device_id → channel（同 device 新连接踢旧连接）。
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, Timer> _pingTimers = {};

  /// 主机最近一次广播出去的任务状态：`GET /api/v1/tasks/active` 的回放依据
  /// （安卓端每秒轮询的兜底，与 Desktop 版同构）。
  _TaskStateSnapshot? _lastTaskState;

  /// 进行中的**本机**截屏任务：手机正好在识别过程中连上来时补发一次，
  /// 否则它会一直停在「没有任务」。
  _LocalTaskState? _pendingLocalTask;

  QuizSyncServer({
    required this.store,
    required this.tasks,
    required this.log,
    this.options = const ServerOptions(),
    String? controlToken,
    int Function()? now,
  })  : controlToken = controlToken ?? generateTokenHex(),
        now = now ?? nowMs {
    _pairingExpiresAt = this.now() + options.pairingTtl.inMilliseconds;
  }

  int? get port => _port;
  String get pairingCode => _pairingCode;
  int get pairingExpiresAt => _pairingExpiresAt;
  String get deviceId => store.deviceId;
  String get serverName => store.serverName;

  int get connectedCount => _connections.length;
  List<String> get connectedDeviceIds => _connections.keys.toList();

  /// 刷新配对码（CLI 的 `pair` 命令与过期自动刷新都用它）。
  String refreshPairingCode() {
    _pairingCode = generatePairingCode();
    _pairingExpiresAt = now() + options.pairingTtl.inMilliseconds;
    onStateChanged?.call();
    return _pairingCode;
  }

  /// 配对码已过期且还没有任何设备配对上 → 自动换一个新的。
  ///
  /// 需求里 CLI 要一直显示配对码；5 分钟就失效的话用户回来时那张二维码已经
  /// 没用了，而他看不出区别（扫码只会得到「配对码已过期」）。
  bool ensureFreshPairingCode() {
    if (now() <= _pairingExpiresAt) return false;
    refreshPairingCode();
    return true;
  }

  /// 绑定 0.0.0.0：默认 8765，占用则探测 8766–8770。
  Future<int> start() async {
    final handler = const Pipeline()
        .addMiddleware(_middleware)
        .addHandler((req) => _router(req));
    Object? lastError;
    for (var p = options.preferredPort;
        p < options.preferredPort + options.portRange;
        p++) {
      try {
        _httpServer =
            await HttpServer.bind(InternetAddress.anyIPv4, p, shared: false);
        _port = _httpServer!.port;
        shelf_io.serveRequests(_httpServer!, handler);
        return _port!;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw StateError('端口 ${options.preferredPort}-'
        '${options.preferredPort + options.portRange - 1} 全部被占用: $lastError');
  }

  Future<void> stop() async {
    for (final t in _pingTimers.values) {
      t.cancel();
    }
    _pingTimers.clear();
    // 先快照再关：sink.close() 的 await 期间连接的 onDone 会把条目从
    // _connections 里删掉，直接遍历 values 会 ConcurrentModificationError。
    final channels = _connections.values.toList();
    _connections.clear();
    for (final ws in channels) {
      try {
        await ws.sink.close();
      } catch (_) {
        // 已经断开的连接直接忽略。
      }
    }
    await _httpServer?.close(force: true);
    _httpServer = null;
    _port = null;
  }

  Router get _router => Router()
    ..get('/api/v1/info', _handleInfo)
    ..post('/api/v1/pair', _handlePair)
    ..post('/api/v1/images', _handleImageUpload)
    ..get('/api/v1/images/<hash>', _handleImageDownload)
    ..post('/api/v1/tasks', _handleTaskCreate)
    // 静态路径必须排在 `<taskId>` 之前：shelf_router 取**第一个**匹配的路由。
    ..get('/api/v1/tasks/active', _handleActiveTask)
    ..get('/api/v1/tasks/<taskId>', _handleTaskGet)
    ..post('/api/v1/tasks/<taskId>/retry', _handleTaskRetry)
    ..post('/api/v1/sessions/<sessionId>/reanalyze', _handleSessionReanalyze)
    ..get('/api/v1/collections', _handleCollections)
    ..post('/api/v1/collections/<id>/select', _handleCollectionSelect)
    ..post('/api/v1/sync/ops', _handleOpsPush)
    ..get('/api/v1/sync/ops', _handleOpsPull)
    ..get('/api/v1/sync/snapshot', _handleSnapshot)
    ..get('/api/v1/devices', _handleDevices)
    ..delete('/api/v1/devices/<id>', _handleDeviceRevoke)
    // 本机停机开关（无窗口后台模式用）：只接受回环地址 + 控制令牌。
    ..post('/api/v1/shutdown', _handleShutdown)
    // 本机命令行转发（后台运行后重新打开窗口时的命令提示符）：同样只认回环 + 令牌。
    ..post('/api/v1/console', _handleConsole)
    ..get('/ws', _handleWs);

  // ------------------------------------------------------------
  // 中间件：版本头 + 鉴权（除 /pair 与 /info 外全要 token）
  // ------------------------------------------------------------

  Middleware get _middleware => (inner) => (request) async {
        Response? authFailure;
        final path = request.url.path;
        // /ws 升级后的连接不做任何 response 改写，避免破坏已劫持的 socket。
        if (path == 'ws') return inner(request);
        // 本机停机开关 / 命令行转发走自己的令牌（不是配对 token），不参与 Bearer 鉴权。
        if (path == 'api/v1/shutdown' || path == 'api/v1/console') {
          return inner(request);
        }
        if (path != 'api/v1/pair' && path != 'api/v1/info') {
          final status = _authStatus(request);
          if (status == AuthStatus.missing) {
            authFailure = _error(401, 'unauthorized', '缺少 token');
          } else if (status == AuthStatus.revoked) {
            authFailure = _error(401, 'revoked', '设备已被吊销');
          } else if (status == AuthStatus.invalid) {
            authFailure = _error(401, 'unauthorized', 'token 无效');
          }
        }
        // M47：版本协商（protocol.md 2.1）：主版本不一致 → 426。
        authFailure ??= _versionMismatch(request);
        final response = await (authFailure == null
            ? inner(request)
            : Future<Response>.value(authFailure));
        return response.change(headers: {
          'X-QS-Server-Version': options.appVersion,
          ...response.headers,
        });
      };

  /// 主版本不一致 → 426（body 里给出双方版本）；不带这个头的请求放行。
  Response? _versionMismatch(Request request) {
    final client = request.headers['x-qs-client-version']?.trim() ?? '';
    if (client.isEmpty) return null;
    final server = options.appVersion;
    String major(String v) => v.split('.').first;
    if (major(client) == major(server)) return null;
    return _error(426, 'version_mismatch',
        '客户端版本 $client 与服务端 $server 主版本不一致，请两端都升级到同一大版本');
  }

  String? _bearerToken(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    final token = header.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  AuthStatus _authStatus(Request request) {
    final token = _bearerToken(request);
    if (token == null) return AuthStatus.missing;
    final device = store.deviceByTokenHash(sha256Hex(token.codeUnits));
    if (device == null) return AuthStatus.invalid;
    return device.info.isRevoked ? AuthStatus.revoked : AuthStatus.valid;
  }

  String? _authDeviceId(Request request) {
    final token = _bearerToken(request);
    if (token == null) return null;
    final device = store.deviceByTokenHash(sha256Hex(token.codeUnits));
    if (device == null || device.info.isRevoked) return null;
    return device.info.deviceId;
  }

  Response _error(int status, String code, String message,
      {int? retryAfterSeconds}) {
    return Response(status,
        body: jsonEncode({
          'code': code,
          'message': message,
          'retry_after_seconds': retryAfterSeconds,
        }),
        headers: {'content-type': 'application/json; charset=utf-8'});
  }

  Response _json(Object data, {int status = 200}) => Response(status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json; charset=utf-8'});

  // ------------------------------------------------------------
  // 端点：信息 / 配对
  // ------------------------------------------------------------

  Response _handleInfo(Request request) {
    final config = tasks.configProvider();
    return _json({
      'device_id': store.deviceId,
      'device_name': store.serverName,
      'platform': 'windows',
      'protocol_version': options.protocolVersion,
      'app_version': options.appVersion,
      'ai_configured': config.configured,
      'active_collection_id': store.collection.collectionId,
      'active_collection_name': store.collection.name,
      // Desktop 版报的能力集；Server 全都实现（同一条协议），照原样上报。
      'capabilities': ['analyze', 'sync', 'image_fetch', 'collections', 'multipage'],
    });
  }

  Future<Response> _handlePair(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _error(400, 'invalid_request', 'body 不是合法 JSON');
    }
    final req = PairRequest.fromJson(body);
    if (!req.isValid) {
      return _error(400, 'invalid_request', '字段缺失或格式错误');
    }

    final ts = now();
    if (ts < _lockedUntil) {
      return _error(429, 'rate_limited', '失败次数过多已锁定',
          retryAfterSeconds: ((_lockedUntil - ts) / 1000).ceil());
    }
    _pairAttemptTimestamps.removeWhere((t) => ts - t > 60000);
    if (_pairAttemptTimestamps.length >= options.pairAttemptsPerMinute) {
      return _error(429, 'rate_limited', '尝试过于频繁',
          retryAfterSeconds:
              ((60000 - (ts - _pairAttemptTimestamps.first)) / 1000).ceil());
    }
    _pairAttemptTimestamps.add(ts);

    try {
      if (req.code != _pairingCode) {
        throw _PairFailure(401, 'invalid_code', '配对码错误');
      }
      if (ts > _pairingExpiresAt) {
        throw _PairFailure(401, 'code_expired', '配对码已过期',
            ((ts - _pairingExpiresAt) / 1000).clamp(0, 60).toInt());
      }

      final existing = store.devices[req.deviceId];
      // 重新配对：签发新 token（覆盖 hash = 旧 token 作废）。
      final token = generateTokenHex();
      await store.upsertDevice(PairedDevice(
        info: DeviceInfo(
          deviceId: req.deviceId,
          name: req.deviceName,
          platform: req.platform,
          tokenHash: sha256Hex(token.codeUnits),
          pairedAt: existing?.info.pairedAt ?? ts,
          lastSeenAt: ts,
          revokedAt: null,
          appVersion: req.appVersion,
        ),
        tokenHash: sha256Hex(token.codeUnits),
      ));
      _pairFailures = 0;
      log.log('手机', '配对成功：${req.deviceName}（${req.platform}）');
      onStateChanged?.call();
      return _json({
        'token': token,
        'server_device_id': store.deviceId,
        'server_name': store.serverName,
        'protocol_version': options.protocolVersion,
        if (existing != null) 'already_paired': true,
      }, status: existing != null ? 409 : 200);
    } on _PairFailure catch (e) {
      _pairFailures++;
      if (_pairFailures >= options.pairFailureLockThreshold) {
        _lockedUntil = ts + options.pairLockout.inMilliseconds;
        _pairFailures = 0;
      }
      return _error(e.status, e.code, e.message,
          retryAfterSeconds: e.retryAfterSeconds);
    }
  }

  // ------------------------------------------------------------
  // 端点：图片
  // ------------------------------------------------------------

  /// 回 4xx/413 之前把已经在路上的请求体吞掉，最多等 300ms
  /// （与 Desktop 内置服务端同一条规则：早回 + 有界，不读完整包）。
  Future<void> _drainBody(Request request,
      {Duration timeout = const Duration(milliseconds: 300)}) async {
    final done = Completer<void>();
    unawaited(() async {
      try {
        var read = 0;
        final cap = options.maxImageBytes + 8 * 1024 * 1024;
        await for (final chunk in request.read()) {
          read += chunk.length;
          if (read > cap) break;
        }
      } catch (_) {
        // 客户端已经断了：反正要回错误，不用管。
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }());
    await Future.any<void>([done.future, Future<void>.delayed(timeout)]);
  }

  Future<Response> _handleImageUpload(Request request) async {
    // M47（SPEC §10 / protocol.md 3.2）：上传接口每分钟 30 次，与 Desktop 版同一口径。
    final caller = _authDeviceId(request);
    final limited = _checkUploadRate(caller ?? '');
    if (limited != null) {
      await _drainBody(request);
      return limited;
    }
    // 先按 Content-Length 拦一道：否则整个 part 会先进内存再判大小。
    final declared = request.contentLength;
    if (declared != null && declared > options.maxImageBytes + 64 * 1024) {
      await _drainBody(request);
      return _error(413, 'payload_too_large', '单文件需 ≤ 2MB');
    }
    final form = request.formData();
    if (form == null) {
      await _drainBody(request);
      return _error(400, 'invalid_request', '需要 multipart/form-data');
    }
    await for (final field in form.formData) {
      if (field.name != 'file') continue;
      // M47：上面那道预检依赖 Content-Length —— 分块传输（chunked）时它是 null，
      // 于是「整块读进内存再判大小」照样能被吃爆内存。这里边收边计数，一超限
      // 立刻 413 并停止读取（与 Desktop 版 `_handleImageUpload` 一致）。
      final builder = BytesBuilder(copy: false);
      var tooLarge = false;
      await for (final chunk in field.part) {
        builder.add(chunk);
        if (builder.length > options.maxImageBytes) {
          tooLarge = true;
          break;
        }
      }
      if (tooLarge) {
        await _drainBody(request);
        return _error(413, 'payload_too_large', '单文件需 ≤ 2MB');
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        await _drainBody(request);
        return _error(400, 'invalid_request', '文件内容为空');
      }
      if (bytes.length > options.maxImageBytes) {
        await _drainBody(request);
        return _error(413, 'payload_too_large', '单文件需 ≤ 2MB');
      }
      final existed = store.images[sha256Hex(bytes)] != null;
      final meta = await store.writeImage(bytes);
      return _json({
        'image_hash': meta.hash,
        'size': meta.size,
        'mime': meta.mime,
        'width': meta.width,
        'height': meta.height,
        'existed': existed,
      });
    }
    return _error(400, 'invalid_request', '缺少 file 字段');
  }

  /// 上传接口的滑窗限流（每台设备每分钟 [ServerOptions.imageUploadsPerMinute] 次）。
  /// 通过返回 null；被限流返回 429。
  Response? _checkUploadRate(String deviceId) {
    if (options.imageUploadsPerMinute <= 0) return null;
    final ts = now();
    final list = _uploadTimestamps.putIfAbsent(deviceId, () => <int>[]);
    list.removeWhere((t) => ts - t > 60000);
    if (list.length >= options.imageUploadsPerMinute) {
      return _error(429, 'rate_limited', '上传过于频繁',
          retryAfterSeconds: ((60000 - (ts - list.first)) / 1000).ceil());
    }
    list.add(ts);
    return null;
  }

  Future<Response> _handleImageDownload(Request request, String hash) async {
    // 只接受 64 位十六进制（与 Desktop 内置服务端同一条规则）：hash 直接拼进
    // 文件名，不校验就是目录穿越（Windows 上 `\` 也是分隔符）。
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      return _error(404, 'not_found', '图片不存在');
    }
    final bytes = await store.readImage(hash);
    if (bytes == null) return _error(404, 'not_found', '图片不存在');
    return Response.ok(bytes, headers: {'content-type': 'image/jpeg'});
  }

  // ------------------------------------------------------------
  // 端点：任务
  // ------------------------------------------------------------

  /// `POST /api/v1/tasks`：手机发起识别（协议兼容端点）。
  ///
  /// 需求把 Server 的功能冻结为「截图 → AI → 推给手机」，但 Android 端在
  /// 手机上发起识别时打的**就是**这个端点。不实现它，用户一按手机悬浮球就会
  /// 看到「主机返回错误」——那是功能回归，不是「没有多余功能」。
  /// 所以这里照协议的语义实现，复用**同一条**识别流水线（不引入任何新能力）。
  Future<Response> _handleTaskCreate(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _error(400, 'invalid_request', 'body 不是合法 JSON');
    }
    final taskId = body['task_id']?.toString();
    final imageHash = body['image_hash']?.toString();

    final rawHashes = body['image_hashes'];
    var hashes = <String>[];
    if (rawHashes is List) {
      hashes = rawHashes
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (imageHash != null && imageHash.isNotEmpty) {
      hashes = [imageHash];
    }
    if (taskId == null || taskId.isEmpty || hashes.isEmpty) {
      return _error(400, 'invalid_request', 'task_id / image_hash 缺失');
    }
    if (hashes.length > kHardMaxPagesPerTask) {
      return _error(400, 'too_many_pages',
          '一次最多 $kHardMaxPagesPerTask 页（当前 ${hashes.length} 页）');
    }
    for (final h in hashes) {
      if (store.images[h] == null) {
        return _error(400, 'invalid_request', 'image_hash 未上传');
      }
    }

    final requestedCollection = body['collection_id']?.toString();
    final collectionId =
        (requestedCollection != null && requestedCollection.isNotEmpty)
            ? requestedCollection
            : store.collection.collectionId;
    if (collectionId != store.collection.collectionId) {
      return _error(409, 'no_active_collection', kNoCollectionMessage);
    }

    final force = body['force_reanalyze'] == true;
    // M47（与 Desktop 版 C4 对齐）：Server 的任务链路是**串行**的（`ServerTasks`
    // 用 `_busy` 挡并发），没有队列可排队 —— 所以这里在「已经有一条在跑」时
    // 直接回 429，而不是先答应 202、再让那条任务以 `busy` 失败（手机端看到的是
    // 「排队中」然后莫名其妙失败）。
    if (tasks.busy) {
      return _error(429, 'queue_full', '已有识别正在进行，请稍后重试',
          retryAfterSeconds: 5);
    }
    if (!force) {
      final reusable = tasks.findReusable(hashes);
      if (reusable != null) {
        return _json({
          'status': 'done',
          'session_id': reusable.session.sessionId,
          'question_count': reusable.questions.length,
          'cached': true,
        }, status: 202);
      }
    }

    final pages = <PageInput>[];
    for (final hash in hashes) {
      final bytes = await store.readImage(hash);
      if (bytes == null) {
        return _error(400, 'invalid_request', 'image_hash 未上传');
      }
      pages.add(PageInput(hash: hash, jpeg: bytes, width: 0, height: 0));
    }

    final sessionId = newUuidV4();
    final source = body['source_device']?.toString() ?? store.deviceId;
    unawaited(tasks.run(
      pages: pages,
      sourceDevice: source,
      collectionId: collectionId,
      taskId: taskId,
      sessionId: sessionId,
    ));
    return _json({
      'status': 'queued',
      'session_id': sessionId,
      'question_count': null,
      'cached': false,
    }, status: 202);
  }

  /// `GET /api/v1/tasks/active`：安卓端每秒一次的**只读**状态探测
  /// （WS 推送的兜底）。与 Desktop 版同构，字段一个不少。
  Response _handleActiveTask(Request request) {
    final state = _lastTaskState;
    Map<String, dynamic>? sessionJson;
    String? message;
    if (state != null && state.sessionId != null) {
      final stored = store.getSession(state.sessionId!);
      if (stored != null && !stored.session.isDeleted) {
        if (state.status == 'done') sessionJson = stored.toProtocolJson();
        if (state.status == 'failed') {
          message = stored.session.errorMessage ?? '分析失败';
        }
      }
    }
    return _json({
      'status': state?.status ?? 'idle',
      'task_id': state?.taskId,
      'session_id': state?.sessionId,
      'image_count': state?.imageCount ?? 0,
      'updated_at': state?.at ?? 0,
      'message': message,
      'active_collection_id': store.collection.collectionId,
      'active_collection_name': store.collection.name,
      'collections': [store.collection.toJson()],
      // Server 不产生同步 op（只有单向的「截图 → AI → 推结果」），
      // 恒为 0 → 安卓端不会做无谓的 ops 拉取。
      'ops_lamport': 0,
      'session': ?sessionJson,
    });
  }

  /// 按 task_id 找会话（Server 没有独立的任务表：`Session.taskId` 就是索引，
  /// 本机截屏任务的 task_id 直接等于 session_id）。
  StoredSession? _sessionByTaskId(String taskId) {
    for (final stored in store.sessions.values) {
      if (stored.session.taskId == taskId ||
          stored.session.sessionId == taskId) {
        return stored;
      }
    }
    return null;
  }

  Response _handleTaskGet(Request request, String taskId) {
    final stored = _sessionByTaskId(taskId);
    if (stored == null) return _error(404, 'not_found', '任务不存在');
    return _json({
      'task_id': stored.session.taskId ?? taskId,
      'status': stored.session.status.wire,
      'session_id': stored.session.sessionId,
      'error_code': stored.session.errorCode,
      'error_message': stored.session.errorMessage,
      'session': stored.toProtocolJson(),
    });
  }

  Future<Response> _handleTaskRetry(Request request, String taskId) async {
    final stored = _sessionByTaskId(taskId);
    if (stored == null) return _error(404, 'not_found', '任务不存在');
    await tasks.retrySession(stored.session.sessionId);
    return _json({'status': 'queued'});
  }

  /// 「重新生成」（安卓结果页的按钮）：按既有页序起一个新会话再跑一次。
  Future<Response> _handleSessionReanalyze(
      Request request, String sessionId) async {
    if (store.getSession(sessionId) == null) {
      return _error(404, 'not_found', '会话不存在');
    }
    final newSessionId = await tasks.startReanalyze(
        sessionId, _authDeviceId(request) ?? store.deviceId);
    if (newSessionId == null) {
      return _error(409, 'invalid_request', '原图已不在电脑上，无法重新识别');
    }
    return _json({
      'status': 'queued',
      'session_id': newSessionId,
      'question_count': null,
      'cached': false,
    }, status: 202);
  }

  // ------------------------------------------------------------
  // 端点：合集 / 同步 / 设备
  // ------------------------------------------------------------

  Response _handleCollections(Request request) => _json({
        'collections': [store.collection.toJson()],
        'active_collection_id': store.collection.collectionId,
      });

  Future<Response> _handleCollectionSelect(Request request, String id) async {
    if (id != store.collection.collectionId) {
      return _error(404, 'not_found', '合集不存在');
    }
    await notifyCollectionChanged();
    return _json({'active_collection_id': id});
  }

  /// 广播当前合集（安卓端切换合集后回执；Server 只有一个合集）。
  Future<void> notifyCollectionChanged() async {
    broadcast({
      'type': 'collection_changed',
      'collection_id': store.collection.collectionId,
      'collection_name': store.collection.name,
    });
  }

  Future<Response> _handleOpsPush(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _error(400, 'invalid_request', 'body 不是合法 JSON');
    }
    final rawOps = body['ops'];
    if (rawOps is! List) {
      return _error(400, 'invalid_request', 'ops 缺失');
    }
    var applied = 0;
    var rejected = 0;
    // M47：op 的归属必须等于认证设备（与共享包里的内置服务端同一规则）。
    final caller = _authDeviceId(request);
    for (final raw in rawOps) {
      if (raw is! Map) continue;
      final op = SyncOp.fromJson(Map<String, dynamic>.from(raw));
      // 拒绝「声称由主机自己产生」的 op（主机没有任何 op）。
      if (op.deviceId == store.deviceId) continue;
      if (caller == null || op.deviceId != caller) {
        rejected++;
        continue;
      }
      // Server 不做字段级合并（没有第二条写入路径），只做幂等记录，
      // 以免手机端因为「applied 恒为 0」反复重推同一批 op。
      if (store.markOpApplied(op.opId)) applied++;
    }
    if (applied > 0) await store.save();
    return _json({'applied': applied, 'rejected': rejected});
  }

  Response _handleOpsPull(Request request) {
    final fromDevice = request.url.queryParameters['from_device'] ?? '';
    if (fromDevice.isEmpty) {
      return _error(400, 'invalid_request', 'from_device 缺失');
    }
    // 主机不产生 op：永远是一个空页（`has_more: false`），客户端据此结束拉取。
    return _json({'ops': <Object>[], 'has_more': false, 'next_cursor': null});
  }

  /// `GET /api/v1/sync/snapshot`：全量实体的**分页**快照
  /// （`data-model.md` 2.9：返回全量实体（分页））。M47 与 Desktop 版同一口径。
  ///
  /// Server 的存储是 JSON（不是库），但会话一多同样不该一次性全塞进一个响应：
  /// `limit`（默认 200，上限 1000）+ `offset`，题目只带本页涉及的会话。
  Response _handleSnapshot(Request request) {
    final requested =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 200;
    final limit = requested.clamp(1, 1000);
    final offset =
        (int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0)
            .clamp(0, 1 << 30);

    final all = store.sessions.values.toList()
      ..sort((a, b) {
        final byTime = a.session.createdAt.compareTo(b.session.createdAt);
        return byTime != 0
            ? byTime
            : a.session.sessionId.compareTo(b.session.sessionId);
      });
    final page = offset >= all.length
        ? const <StoredSession>[]
        : all.sublist(offset, (offset + limit).clamp(0, all.length));
    final hasMore = offset + page.length < all.length;

    final sessions = <Map<String, dynamic>>[];
    final questions = <Map<String, dynamic>>[];
    for (final stored in page) {
      sessions.add(stored.session.toJson());
      questions.addAll(stored.questions.map((q) => q.toJson()));
    }
    return _json({
      'sessions': sessions,
      'questions': questions,
      'session_images': <Object>[],
      'collections': [store.collection.toJson()],
      'images': store.images.values.map((i) => i.toJson()).toList(),
      // devices 的 toJson 已排除 token_hash。
      'devices': store.devices.values.map((d) => d.info.toJson()).toList(),
      'watermark': 0,
      'has_more': hasMore,
      'next_offset': hasMore ? offset + page.length : null,
    });
  }

  Response _handleDevices(Request request) => _json({
        'devices':
            store.devices.values.map((d) => d.info.toJson()).toList(),
      });

  Future<Response> _handleDeviceRevoke(Request request, String id) async {
    await revokeDeviceAndNotify(id);
    return _json({'revoked': id});
  }

  /// 吊销设备并通知对端（只改本地不给手机发通知的话，手机的 WS 还挂着、
  /// 界面照旧显示已配对）。
  Future<void> revokeDeviceAndNotify(String id) async {
    final device = store.devices[id];
    if (device == null) return;
    await store.revokeDevice(id);
    broadcast({'type': 'device_revoked', 'device_id': id});
    final ws = _connections.remove(id);
    if (ws != null) {
      _pingTimers.remove(id)?.cancel();
      try {
        await ws.sink.close();
      } catch (_) {
        // 连接已断开。
      }
    }
    log.log('手机', '已吊销：${device.info.name}');
    onStateChanged?.call();
  }

  // ------------------------------------------------------------
  // WebSocket
  // ------------------------------------------------------------

  FutureOr<Response> _handleWs(Request request) async {
    final authed = _authDeviceId(request);
    if (authed == null) {
      final status = _authStatus(request);
      return _error(
          401,
          status == AuthStatus.revoked ? 'revoked' : 'unauthorized',
          'WS 握手鉴权失败');
    }
    final handler = webSocketHandler((channel, _) {
      _onWsConnected(authed, channel);
    });
    return handler(request);
  }

  void _onWsConnected(String deviceId, WebSocketChannel channel) {
    // 同 device_id 重复连接：新连接踢掉旧连接（protocol.md 4.4）。
    final old = _connections.remove(deviceId);
    if (old != null) {
      _pingTimers.remove(deviceId)?.cancel();
      old.sink.close();
    }
    _connections[deviceId] = channel;
    final name = store.devices[deviceId]?.info.name ?? deviceId;
    log.log('手机', '已连接：${name.isEmpty ? deviceId : name}');
    // 只通知一次（这里原来还额外叫了一次 onStateChanged，CLI 会跟着把整块面板
    // 再印一遍 —— 用户看到的就是「连上手机后面板弹两次」）。
    onDeviceConnected?.call(deviceId, name);

    // hello（含当前合集：安卓端据此判断能否发起识别）。
    _send(channel, {
      'type': 'hello',
      'server_device_id': store.deviceId,
      'protocol_version': options.protocolVersion,
      'active_collection_id': store.collection.collectionId,
      'active_collection_name': store.collection.name,
    });
    // 手机正好在主机识别过程中连上来时，把进行中的任务补发一次，
    // 否则它会一直停在「没有任务」（只补进行中的，不补已完成的结果）。
    final pending = _pendingLocalTask;
    if (pending != null) {
      unawaited(_emitTaskUpdate(
          pending.sessionId, pending.status, pending.sessionId, pending.imageCount));
    }

    // 心跳：服务端每 30s 发 ping，客户端 10s 内未回 pong 则断开重连。
    _pingTimers[deviceId] = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(channel, {'type': 'ping', 'ts': now()});
    });

    channel.stream.listen(
      (data) => _onWsData(deviceId, channel, data),
      onDone: () => _dropConnection(deviceId, channel),
      onError: (_) => _dropConnection(deviceId, channel),
      cancelOnError: true,
    );
  }

  void _dropConnection(String deviceId, WebSocketChannel channel) {
    if (_connections[deviceId] == channel) {
      _connections.remove(deviceId);
      _pingTimers.remove(deviceId)?.cancel();
      final name = store.devices[deviceId]?.info.name ?? deviceId;
      log.log('手机', '已断开：${name.isEmpty ? deviceId : name}');
      // 同上：只通知一次。
      onDeviceDisconnected?.call(deviceId, name);
    }
  }

  Future<void> _onWsData(
      String deviceId, WebSocketChannel channel, Object data) async {
    try {
      final msg = jsonDecode(data.toString());
      if (msg is! Map) return;
      switch (msg['type']) {
        case 'hello':
          final device = store.devices[deviceId];
          if (device != null) {
            await store.upsertDevice(PairedDevice(
              info: device.info.copyWith(
                  lastSeenAt: now(), appVersion: msg['app_version']?.toString()),
              tokenHash: device.tokenHash,
            ));
          }
          break;
        case 'ack':
        case 'pong':
          // Server 没有 op 要确认；心跳回包也不需要处理。
          break;
        case 'push_ops':
          final ops = msg['ops'];
          if (ops is List) {
            var maxLamport = 0;
            for (final raw in ops) {
              if (raw is! Map) continue;
              final op = SyncOp.fromJson(Map<String, dynamic>.from(raw));
              if (op.deviceId == store.deviceId) continue;
              // M47：同 HTTP —— 不能替**别的设备**记账。
              if (op.deviceId != deviceId) continue;
              store.markOpApplied(op.opId);
              if (op.lamport > maxLamport) maxLamport = op.lamport;
            }
            await store.save();
            _send(channel, {'type': 'ack', 'watermark_lamport': maxLamport});
          }
          break;
      }
    } catch (_) {
      // 无效消息直接忽略（协议向前兼容）。
    }
  }

  void _send(WebSocketChannel channel, Object message) {
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      // 连接已断开。
    }
  }

  /// 广播给所有已连接客户端（Map 由 _send 统一编码，勿双重编码）。
  void broadcast(Object message) {
    for (final channel in _connections.values) {
      _send(channel, message);
    }
  }

  /// 本机停机开关：`POST /api/v1/shutdown`。
  ///
  /// 两道门槛，缺一不可：
  ///  1. **回环地址**（`127.0.0.1`/`::1`）：局域网里的手机与别的机器一律拒绝；
  ///  2. `X-QS-Control` 头必须等于 [controlToken]，而那个值只写在数据目录的
  ///     `runtime.json` 里，只有本机的 `--stop` 读得到。
  ///
  /// 这样无窗口后台运行时，用户还有一条优雅停机的路（等价于点 `quit` / Ctrl+C），
  /// 而不是只能去任务管理器里结束进程。
  Future<Response> _handleShutdown(Request request) async {
    final info = request.context['shelf.io.connection_info'];
    final remote = info is HttpConnectionInfo ? info.remoteAddress : null;
    if (remote == null || !remote.isLoopback) {
      return _error(403, 'forbidden', '只允许本机停止服务');
    }
    if (request.headers['x-qs-control'] != controlToken) {
      return _error(403, 'forbidden', '缺少或错误的控制令牌');
    }
    log.log('服务器', '收到本机 --stop 停机请求');
    // 先把响应发出去，再走停机流程：不然连接可能来不及拿到回复。
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      onShutdownRequested?.call();
    });
    return _json({'stopping': true});
  }

  /// 本机命令行转发：`POST /api/v1/console`，body `{"command": "status"}`。
  ///
  /// 为什么需要它：`hidden` 之后进程**脱离控制台**了（窗口真的没了、关掉终端也不
  /// 影响它），可用户还想要一个「敲命令的地方」。做法就是再启动一次同一个 exe ——
  /// 它发现已经有实例在跑，就不再起第二个服务，而是当那个实例的命令行窗口，每条
  /// 命令经这个端点送进来执行、输出原样带回去。
  ///
  /// 门槛与停机接口完全一致：**只接受回环地址 + `X-QS-Control` 令牌**（令牌只写在
  /// 本机数据目录的 `runtime.json` 里）。局域网里的手机与别的机器一律 403。
  Future<Response> _handleConsole(Request request) async {
    final info = request.context['shelf.io.connection_info'];
    final remote = info is HttpConnectionInfo ? info.remoteAddress : null;
    if (remote == null || !remote.isLoopback) {
      return _error(403, 'forbidden', '只允许本机使用命令行');
    }
    if (request.headers['x-qs-control'] != controlToken) {
      return _error(403, 'forbidden', '缺少或错误的控制令牌');
    }
    final handler = onConsoleCommand;
    if (handler == null) {
      return _error(501, 'unavailable', '这个实例没有开放本机命令行');
    }
    String command = '';
    try {
      final body = await request.readAsString();
      if (body.trim().isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          return _error(400, 'bad_request', '请求体需要是 {"command": "..."}');
        }
        command = decoded['command']?.toString() ?? '';
      }
    } catch (_) {
      return _error(400, 'bad_request', '请求体需要是 {"command": "..."}');
    }
    if (command.trim().isEmpty) {
      return _json({'output': ''});
    }
    try {
      final output = await handler(command);
      return _json({'output': output});
    } catch (e) {
      return _json({'output': '[错误] 命令执行失败：$e\n'});
    }
  }

  /// 任务状态变化的唯一出口：广播 `task_update`，终态再补 `task_result` /
  /// `task_failed`，并把这次状态记下来供 `GET /api/v1/tasks/active` 回放。
  void notifyTaskUpdate(String taskId, String status, String? sessionId,
      {int imageCount = 0}) {
    unawaited(_emitTaskUpdate(taskId, status, sessionId, imageCount));
  }

  Future<void> _emitTaskUpdate(String taskId, String status, String? sessionId,
      int imageCount) async {
    var count = imageCount;
    if (count <= 0 && sessionId != null && sessionId.isNotEmpty) {
      count = store.getSession(sessionId)?.imageHashes.length ?? 0;
    }
    // 只补发「进行中」的本机任务：已完成的不补，否则手机每次重连都会跳到
    // 上一次的结果页。
    _pendingLocalTask = (status == 'queued' || status == 'analyzing')
        ? _LocalTaskState(sessionId ?? taskId, status, count)
        : null;
    _lastTaskState = _TaskStateSnapshot(taskId, sessionId, status, count, now());
    broadcast({
      'type': 'task_update',
      'task_id': taskId,
      'status': status,
      'session_id': ?sessionId,
      'image_count': count,
    });
    if (sessionId == null) return;
    final stored = store.getSession(sessionId);
    if (stored == null) return;
    if (status == 'done') {
      broadcast({
        'type': 'task_result',
        'task_id': taskId,
        'session': stored.toProtocolJson(),
      });
      log.log('同步', '识别结果已推送给手机');
    } else if (status == 'failed') {
      broadcast({
        'type': 'task_failed',
        'task_id': taskId,
        'error_code': stored.session.errorCode ?? 'internal',
        'message': stored.session.errorMessage ?? '分析失败',
      });
    }
  }

  /// 把某个已完成会话的结果重新推一遍（同图复用命中时用：
  /// 手机端要看到「这次识别」的结果，而不是重启后什么都没有）。
  void pushExistingResult(StoredSession stored) {
    final taskId = stored.session.taskId ?? stored.session.sessionId;
    _lastTaskState = _TaskStateSnapshot(
        taskId, stored.session.sessionId, 'done', stored.imageHashes.length, now());
    _pendingLocalTask = null;
    broadcast({
      'type': 'task_update',
      'task_id': taskId,
      'status': 'done',
      'session_id': stored.session.sessionId,
      'image_count': stored.imageHashes.length,
    });
    broadcast({
      'type': 'task_result',
      'task_id': taskId,
      'session': stored.toProtocolJson(),
    });
    log.log('同步', '识别结果已推送给手机');
  }
}

/// 进行中的本机截屏任务状态：手机连上来时用它补发一次。
class _LocalTaskState {
  final String sessionId;
  final String status;
  final int imageCount;

  const _LocalTaskState(this.sessionId, this.status, this.imageCount);
}

/// 主机最近一次广播出去的任务状态：HTTP 轮询端点的回放依据。
class _TaskStateSnapshot {
  final String taskId;
  final String? sessionId;
  final String status;
  final int imageCount;
  final int at;

  const _TaskStateSnapshot(
      this.taskId, this.sessionId, this.status, this.imageCount, this.at);
}
