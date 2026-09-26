import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:quizsync_core/quizsync_core.dart';

class QuizSyncServerOptions {
  final int preferredPort;
  final int portRange;
  final String appVersion;
  final int protocolVersion;
  final Duration pairingTtl;
  final int pairAttemptsPerMinute;
  final int pairFailureLockThreshold;
  final Duration pairLockout;
  final int maxImageBytes;
  final int syncPageSize;

  /// 上传接口限流：每台设备每分钟最多多少次（`SPEC.md` §10 / `protocol.md` §3.2）。
  /// ≤ 0 表示不限流（供单测批量上传用）。
  final int imageUploadsPerMinute;

  /// 任务队列深度上限（M47）：排队中的任务达到这个数就回 429，
  /// 免得主机被一个客户端的连点灌满、tasks 表无限膨胀。
  final int maxQueueDepth;

  const QuizSyncServerOptions({
    this.preferredPort = 8765,
    this.portRange = 6,
    this.appVersion = '1.0.0',
    this.protocolVersion = 1,
    this.pairingTtl = const Duration(minutes: 5),
    this.pairAttemptsPerMinute = 5,
    this.pairFailureLockThreshold = 10,
    this.pairLockout = const Duration(seconds: 60),
    this.maxImageBytes = 2 * 1024 * 1024,
    this.syncPageSize = 500,
    this.imageUploadsPerMinute = 30,
    this.maxQueueDepth = 20,
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

/// Windows 内置服务端（protocol.md 全部端点 + /ws）。
/// 纯 Dart，回环测试直接实例化。
class QuizSyncServer {
  final CoreRepository repo;
  final ImageFileStore imageStore;
  final ServerTaskExecutor executor;
  final String deviceId;
  final String serverName;
  final QuizSyncServerOptions options;
  final int Function() now;

  /// 任务状态变化的旁路回调（用户反馈 12）：桌面端据此在「手机提交的任务」
  /// 开始/结束时弹到前台；不改协议、不影响广播。
  ///
  /// **只对手机提交的任务触发**。本机截屏（[notifyLocalSession]）走的是
  /// 「后台静默识别」，绝不能经过这里，否则 Windows 一按热键主窗口就自己跳出来
  /// （用户反馈 M14 第 6 条）。
  void Function(String status, String? sessionId)? onTaskUpdateHook;

  /// 正在进行中的**本机**截屏任务（M14 第 6 条）。
  ///
  /// 手机可能在识别过程中才连上 / 断线重连（`SyncSocket` 有心跳与退避重连），
  /// 那样它会漏掉 `task_update`，界面就停在「没有任务」，用户看到的正是
  /// 「主机按了热键，手机毫无反应」。所以记住最后一次进行中的本机任务，
  /// 在 WS 握手时补发一次。**只补进行中**的：已完成的不补，否则手机每次
  /// 重连都会跳到上一次的结果页。
  _LocalTaskState? _pendingLocalTask;

  /// 主机最近一次广播出去的任务状态（用户反馈 M15 第 4 条）。
  ///
  /// WS 是推送式的：断线期间发生的事一点痕迹都不留，所以安卓端加了 HTTP 轮询
  /// 兜底，要问「主机现在 / 刚刚在识别什么」。所有任务状态都从
  /// [_emitTaskUpdate] 这一个出口广播，顺手在那里记一份供只读端点回放。
  ///
  /// 只放内存：它只用做「这一秒和上一秒有没有变化」的比较，主机重启后回到
  /// `idle`（不补发旧结果）也符合语义 —— 与 [_pendingLocalTask] 同一考虑。
  _TaskStateSnapshot? _lastTaskState;

  HttpServer? _httpServer;
  int? _port;

  // 配对状态。
  String _pairingCode = generatePairingCode();
  late int _pairingExpiresAt;

  // 限速窗口。
  final List<int> _pairAttemptTimestamps = [];
  int _pairFailures = 0;
  int _lockedUntil = 0;

  /// 设备 → 最近一次**已认证请求**的时刻。
  ///
  /// 手机端在前台时每秒问一次 `/tasks/active`（`HostStatusPoller`），那条路径
  /// **不建 WS** —— 设置页只看 `connectedCount`（WS 连接数）的话，手机明明正在用，
  /// 界面却一直停在「等待手机连接」（用户实测反馈 M47）。所以「在线」的判据改成
  /// 「WS 连着 **或** 最近 [kActiveDeviceWindowMs] 内有已认证请求」。
  final Map<String, int> _lastAuthedAt = {};

  /// 多久没动静就算不在线（手机 1 秒一轮，取 15 秒留足抖动余量）。
  static const int kActiveDeviceWindowMs = 15000;

  /// 配对失败计数与锁定期落库（M47）：原来只在内存里，重启即清零 ——
  /// 攻击者只要让服务重启一次就能继续猜配对码。
  static const String _kPairFailKey = 'pair_fail_count';
  static const String _kPairLockKey = 'pair_locked_until';

  Future<void> _loadPairGuard() async {
    try {
      _pairFailures =
          int.tryParse(await repo.getSetting(_kPairFailKey) ?? '') ?? 0;
      _lockedUntil =
          int.tryParse(await repo.getSetting(_kPairLockKey) ?? '') ?? 0;
      if (_lockedUntil != 0 && now() >= _lockedUntil) {
        _lockedUntil = 0;
        _pairFailures = 0;
      }
    } catch (_) {
      // 读库失败按「没有历史」处理。
    }
  }

  Future<void> _savePairGuard() async {
    try {
      await repo.setSetting(_kPairFailKey, '$_pairFailures');
      await repo.setSetting(_kPairLockKey, '$_lockedUntil');
    } catch (_) {
      // 写库失败不影响本次配对流程。
    }
  }

  /// 上传接口的滑窗（每台设备各自一份）。
  final Map<String, List<int>> _uploadTimestamps = {};

  // WS 连接表：device_id → channel（同 device 新连接踢旧连接）。
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, Timer> _pingTimers = {};

  QuizSyncServer({
    required this.repo,
    required this.imageStore,
    required this.executor,
    required this.deviceId,
    required this.serverName,
    this.options = const QuizSyncServerOptions(),
    int Function()? now,
  }) : now = now ?? nowMs {
    _pairingExpiresAt = this.now() + options.pairingTtl.inMilliseconds;
  }

  int? get port => _port;
  String get pairingCode => _pairingCode;
  int get pairingExpiresAt => _pairingExpiresAt;

  /// 当前有多少台设备正通过 WebSocket 连着（M9 连接状态用；只读，不改协议）。
  int get connectedCount => _connections.length;

  /// 当前在线的设备 id（连接状态页显示具体是谁连着）。
  List<String> get connectedDeviceIds => _connections.keys.toList();

  /// 刷新配对码（UI 一键刷新）。
  String refreshPairingCode() {
    _pairingCode = generatePairingCode();
    _pairingExpiresAt = now() + options.pairingTtl.inMilliseconds;
    return _pairingCode;
  }

  /// 绑定 0.0.0.0：默认 8765，占用则探测 8766–8770。
  /// preferredPort 传 0 表示随机端口（测试用）。
  Future<int> start() async {
    executor.onTaskUpdate = notifyTaskUpdate;
    // M47：把上次运行留下的配对失败计数 / 锁定期读回来（重启不再清零）。
    await _loadPairGuard();
    final handler = const Pipeline().addMiddleware(_middleware).addHandler(
          (req) => _router(req),
        );
    Object? lastError;
    for (var p = options.preferredPort;
        p < options.preferredPort + options.portRange;
        p++) {
      try {
        _httpServer =
            await HttpServer.bind(InternetAddress.anyIPv4, p, shared: false);
        _port = _httpServer!.port; // 端口 0 时为系统分配的随机端口
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
    // _connections 里删掉，直接遍历 values 会 ConcurrentModificationError，
    // 异常抛出后又跳过 _httpServer.close()，端口一直占着。
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
  }

  Router get _router => Router()
    ..get('/api/v1/info', _handleInfo)
    ..post('/api/v1/pair', _handlePair)
    ..post('/api/v1/images', _handleImageUpload)
    ..get('/api/v1/images/<hash>', _handleImageDownload)
    ..post('/api/v1/tasks', _handleTaskCreate)
    // 静态路径必须排在 `<taskId>` 之前：shelf_router 取**第一个**匹配的路由，
    // 反过来的话 `/api/v1/tasks/active` 会被当成一个 taskId 去查库（404）。
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
    ..get('/ws', _handleWs);

  // ------------------------------------------------------------
  // 中间件：版本头 + 鉴权（除 /api/v1/pair 与 /api/v1/info 外全要 token）
  // ------------------------------------------------------------

  Middleware get _middleware => (inner) => (request) async {
        Response? authFailure;
        final path = request.url.path;
        // /ws 升级后的连接不做任何 response 改写，避免破坏已劫持的 socket。
        if (path == 'ws') {
          return inner(request);
        }
        if (path != 'api/v1/pair' && path != 'api/v1/info') {
          final status = await _authStatus(request);
          if (status == AuthStatus.missing) {
            authFailure = _error(401, 'unauthorized', '缺少 token');
          } else if (status == AuthStatus.revoked) {
            authFailure = _error(401, 'revoked', '设备已被吊销');
          } else if (status == AuthStatus.invalid) {
            authFailure = _error(401, 'unauthorized', 'token 无效');
          }
        }
        // M47：版本协商（protocol.md 2.1）—— 主版本不一致直接 426，免得两端
        // 用不兼容的载荷互相写坏数据。
        authFailure ??= _versionMismatch(request);
        final response = await (authFailure == null
            ? inner(request)
            : Future<Response>.value(authFailure));
        return response.change(headers: {
          'X-QS-Server-Version': options.appVersion,
          ...response.headers,
        });
      };

  /// 主版本不一致 → 426（body 里给出双方版本）。
  ///
  /// **不带 `X-QS-Client-Version` 的请求一律放行**：老版本客户端与手工 curl
  /// 都没有这个头，把它们全挡在门外没有意义（协议推进时再收紧）。
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

  Future<AuthStatus> _authStatus(Request request) async {
    final token = _bearerToken(request);
    if (token == null) return AuthStatus.missing;
    final hash = sha256Hex(token.codeUnits);
    for (final d in await repo.listDevices()) {
      if (d.tokenHash == hash) {
        if (!d.isRevoked) _lastAuthedAt[d.deviceId] = now();
        return d.isRevoked ? AuthStatus.revoked : AuthStatus.valid;
      }
    }
    return AuthStatus.invalid;
  }

  /// 「在线」的设备：WS 连着的 **加上** 最近有过已认证请求的。
  ///
  /// 手机端轮询走 HTTP，不建 WS；只看 WS 连接数会让设置页一直显示「等待手机连接」。
  Set<String> get activeDeviceIds {
    final ts = now();
    _lastAuthedAt.removeWhere((_, t) => ts - t > kActiveDeviceWindowMs);
    return {..._connections.keys, ..._lastAuthedAt.keys};
  }

  /// 在线的设备数（设置页「当前连接状态」用）。
  int get activeDeviceCount => activeDeviceIds.length;

  /// 当前请求的设备 id（token 有效且未吊销时）。
  Future<String?> _authDeviceId(Request request) async {
    final token = _bearerToken(request);
    if (token == null) return null;
    final hash = sha256Hex(token.codeUnits);
    for (final d in await repo.listDevices()) {
      if (d.tokenHash == hash && !d.isRevoked) return d.deviceId;
    }
    return null;
  }

  /// 上传接口的滑窗限流（每台设备每分钟 [QuizSyncServerOptions.imageUploadsPerMinute] 次）。
  /// 通过返回 null；被限流返回 429 响应。
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
  // 端点
  // ------------------------------------------------------------

  FutureOr<Response> _handleInfo(Request request) async {
    final config = await executor.configProvider();
    final collection = await activeCollection();
    return _json({
      'device_id': deviceId,
      'device_name': serverName,
      'platform': 'windows',
      'protocol_version': options.protocolVersion,
      'app_version': options.appVersion,
      'ai_configured': config != null && config.apiKey.isNotEmpty && config.model.isNotEmpty,
      // 用户需求 12：安卓端识别前必须先确认主机已选中合集。
      'active_collection_id': collection?.collectionId,
      'active_collection_name': collection?.name,
      'capabilities': ['analyze', 'sync', 'image_fetch', 'collections', 'multipage'],
    });
  }

  /// 当前选中的合集；已选择但合集被删除时视为未选择。
  Future<Collection?> activeCollection() async {
    final id = await repo.getSetting(kActiveCollectionKey);
    if (id == null || id.isEmpty) return null;
    return repo.getCollection(id);
  }

  /// 桌面端切换合集后调用：立即广播，安卓端无需等下一次轮询。
  Future<void> notifyCollectionChanged() async {
    final c = await activeCollection();
    _broadcast({
      'type': 'collection_changed',
      'collection_id': c?.collectionId,
      'collection_name': c?.name,
    });
  }

  FutureOr<Response> _handleCollections(Request request) async {
    final collections = await repo.listCollections();
    final active = await activeCollection();
    return _json({
      'collections': collections.map((c) => c.toJson()).toList(),
      'active_collection_id': active?.collectionId,
    });
  }

  /// 安卓端也能切换主机当前合集（用户需求 12 的友好补充：手机上可直接选）。
  FutureOr<Response> _handleCollectionSelect(Request request, String id) async {
    if (await repo.getCollection(id) == null) {
      return _error(404, 'not_found', '合集不存在');
    }
    await repo.setSetting(kActiveCollectionKey, id);
    await notifyCollectionChanged();
    return _json({'active_collection_id': id});
  }

  FutureOr<Response> _handlePair(Request request) async {
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
    // 锁定期。
    if (ts < _lockedUntil) {
      return _error(429, 'rate_limited', '失败次数过多已锁定',
          retryAfterSeconds: ((_lockedUntil - ts) / 1000).ceil());
    }
    // 每分钟最多 5 次尝试。
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

      final existing = (await repo.listDevices())
          .where((d) => d.deviceId == req.deviceId)
          .firstOrNull;

      // 重新配对：签发新 token（覆盖 hash = 旧 token 作废），视为 409 场景。
      final token = generateTokenHex();
      await repo.upsertDevice(DeviceInfo(
        deviceId: req.deviceId,
        name: req.deviceName,
        platform: req.platform,
        tokenHash: sha256Hex(token.codeUnits),
        pairedAt: existing?.pairedAt ?? ts,
        lastSeenAt: ts,
        revokedAt: null,
        appVersion: req.appVersion,
      ));
      _pairFailures = 0;
      await _savePairGuard();
      // M47（protocol.md 2.2）：同 device_id 重新配对 = **409 already_paired**，
      // body 里照样给新 token（旧的已作废），客户端按成功处理即可。
      return _json({
        'token': token,
        'server_device_id': deviceId,
        'server_name': serverName,
        'protocol_version': options.protocolVersion,
        if (existing != null) 'already_paired': true,
      }, status: existing != null ? 409 : 200);
    } on _PairFailure catch (e) {
      _pairFailures++;
      if (_pairFailures >= options.pairFailureLockThreshold) {
        _lockedUntil = ts + options.pairLockout.inMilliseconds;
        _pairFailures = 0;
      }
      await _savePairGuard();
      return _error(e.status, e.code, e.message,
          retryAfterSeconds: e.retryAfterSeconds);
    }
  }

  FutureOr<Response> _handleImageUpload(Request request) async {
    // M47（SPEC §10 / protocol.md 3.2）：上传接口每分钟 30 次。
    final caller = await _authDeviceId(request);
    final limited = _checkUploadRate(caller ?? '');
    if (limited != null) {
      await _drainBody(request);
      return limited;
    }
    // 先按 Content-Length 拦一道：原实现在 multipart 解析完、整个 part 都进
    // 内存之后才判断大小，构造一个超大请求就能把主机内存吃掉。
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
      // 立刻 413 并停止读取。
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
        // 空文件也要先把剩余请求体吃掉：multipart 的结尾边界还没读，
        // 直接返回会让 close 带上未读数据（Windows 发 RST，客户端拿不到 400）。
        await _drainBody(request);
        return _error(400, 'invalid_request', '文件内容为空');
      }
      if (bytes.length > options.maxImageBytes) {
        await _drainBody(request);
        return _error(413, 'payload_too_large', '单文件需 ≤ 2MB');
      }
      final hash = sha256Hex(bytes);
      final existed = await repo.getImage(hash);
      await imageStore.write(hash, bytes);
      final uploader = caller ?? repo.deviceId;
      final localPath = imageStore.pathFor(hash) ?? existed?.localPath;
      // 用户反馈 M15 第 2 条：这里原来在**写完文件之后**又查了一次库，
      // 而写文件并不建 `images` 行，查到的 localPath 必然是 null —— 于是手机
      // 传上来的图片在 Windows 端**永远没有缩略图**（主界面显示占位图标），
      // 结果页与「重新分析」也找不到原图。改成直接用刚落盘的路径。
      await repo.upsertImage(ImageMeta(
        hash: hash,
        size: bytes.length,
        mime: 'image/jpeg',
        // 宽高原样带回既有值：本实现从不解码图片，`upsertImage` 的映射把
        // 「键存在且值为 null」当成**显式写 NULL** —— 传 null 会让同字节重传
        // 把历史行里的尺寸抹掉，而响应又回的是写入前读到的旧值（响应与落库
        // 不一致）。带上既有值既不改语义，也消掉这个不一致。
        width: existed?.width,
        height: existed?.height,
        localPath: localPath,
        createdAt: existed?.createdAt ?? now(),
        uploadedBy: uploader,
      ));
      if (localPath != null && existed?.localPath != localPath) {
        // `upsertImage` 的「有变化吗」判定**不含 local_path**（本地专属列不进 op），
        // 只改这一列时它会走「无变化 → 直接返回」的短路。这里显式写一次，
        // 好让历史数据（记录在、却丢了路径）重传一次就自愈。
        await repo.setImageLocalPath(hash, localPath);
      }
      return _json({
        'image_hash': hash,
        'size': bytes.length,
        'mime': 'image/jpeg',
        'width': existed?.width,
        'height': existed?.height,
        'existed': existed != null,
      });
    }
    return _error(400, 'invalid_request', '缺少 file 字段');
  }

  /// 回 4xx/413 之前把**已经在路上的**请求体吞掉，最多等 [timeout]。
  ///
  /// 为什么需要：提前返回时请求体往往还没读完（multipart 的结尾边界、或超限后
  /// 剩下的页），Windows 上「带未读数据的 close」会发 RST —— 客户端还没读完响应
  /// 就被打断，拿到的是 `Connection closed before full header was received`，
  /// 手机端于是报「网络错误」而不是「图片太大 / 文件为空 / 太频繁」。
  ///
  /// 为什么**不能**读完再回：`upload_limits_test` 钉着「一超过上限就回 413，
  /// **不等整包收完**（内存必须有界）」—— 客户端可能根本不结束请求体。所以这里
  /// 只吞已经到达的字节，到点就走：既保住早回，又让常见超限（多出几十 KB～
  /// 几 MB）能收到干净的响应。丢弃本身是 O(1) 内存的。
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
        // 客户端已经断了：反正要回错误，这里不用管。
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }());
    await Future.any<void>([done.future, Future<void>.delayed(timeout)]);
  }

  FutureOr<Response> _handleImageDownload(Request request, String hash) async {
    // 只接受 64 位十六进制：hash 是直接拼进文件名的（`<dir>/<hash>.jpg`），
    // 不校验就是一条目录穿越 —— Windows 上 `\` 也是路径分隔符，
    // `/api/v1/images/..%5C..%5Cx` 能读到图片目录之外的 .jpg（审计已记）。
    if (!_isSha256Hex(hash)) return _error(404, 'not_found', '图片不存在');
    final bytes = await imageStore.read(hash);
    if (bytes == null) return _error(404, 'not_found', '图片不存在');
    return Response.ok(bytes, headers: {'content-type': 'image/jpeg'});
  }

  static final RegExp _sha256HexRe = RegExp(r'^[0-9a-f]{64}$');

  /// 是不是规范形态的 sha256 十六进制（图片名 / hash 校验用）。
  static bool _isSha256Hex(String s) => _sha256HexRe.hasMatch(s);

  FutureOr<Response> _handleTaskCreate(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _error(400, 'invalid_request', 'body 不是合法 JSON');
    }
    final taskId = body['task_id']?.toString();
    final imageHash = body['image_hash']?.toString();
    final sourceDevice = body['source_device']?.toString();

    // 多页（用户需求 4）：image_hashes 优先；否则退回单页 image_hash。
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
      if (await repo.getImage(h) == null) {
        return _error(400, 'invalid_request', 'image_hash 未上传');
      }
    }

    // 用户需求 8/12：任务必须落在某个合集里。手机端没选合集时不静默塞进
    // 「未分类」——那会让历史记录分组错乱，直接 409 让客户端提示用户。
    final requestedCollection = body['collection_id']?.toString();
    final active = await activeCollection();
    final collectionId = (requestedCollection != null && requestedCollection.isNotEmpty)
        ? requestedCollection
        : active?.collectionId;
    if (collectionId == null || collectionId.isEmpty) {
      return _error(409, 'no_active_collection', '请在电脑端先新建或选择一个任务合集');
    }
    if (await repo.getCollection(collectionId) == null) {
      return _error(409, 'no_active_collection', '所选合集不存在，请重新选择');
    }

    // M47：任务队列深度上限。队列是串行执行的（并发恒 1），没有上限时一个
    // 客户端连点就能让 tasks 表无限膨胀、主机端一直忙着跑旧任务。
    final queuedCount = (await (repo.db.select(repo.db.tasks)
              ..where((t) => t.status.equals('queued')))
            .get())
        .length;
    if (queuedCount >= options.maxQueueDepth) {
      return _error(429, 'queue_full', '主机任务队列已满（$queuedCount），请稍后重试',
          retryAfterSeconds: 10);
    }

    final (status, sessionId) = await executor.submit(
      taskId: taskId,
      imageHash: hashes.first,
      imageHashes: hashes,
      sourceDevice: sourceDevice ?? repo.deviceId,
      collectionId: collectionId,
      forceReanalyze: body['force_reanalyze'] == true,
    );
    // protocol.md 3.3：status/session_id/question_count/cached 四件套。
    // 复用既有会话（同图）时必须给出题目数与 cached=true，否则客户端无法
    // 区分「新分析」与「命中缓存」。
    int? questionCount;
    var cached = false;
    if (sessionId != null) {
      final session = await repo.getSession(sessionId, includeDeleted: true);
      if (session != null) {
        questionCount = session.questionCount;
        cached = session.cached;
      }
    }
    return _json({
      'status': status,
      'session_id': sessionId,
      'question_count': questionCount,
      'cached': cached || status == 'done',
    }, status: 202);
  }

  /// `GET /api/v1/tasks/active`：安卓端每秒一次的**只读**状态探测
  /// （用户反馈 M15 第 4 条：「又没有方法让他一直刷新，比如安卓端 1s 获取
  /// 一次状态」）。
  ///
  /// 为什么不能复用别的端点：`/api/v1/info` 只有主机自述，`/api/v1/tasks/<id>`
  /// 需要客户端先知道 task_id（而本机截屏任务的 task_id 就是 session_id，且
  /// 桌面端的本机截屏**不经过任务队列**，库里没有 tasks 行）。
  ///
  /// 返回内容与 WS 推送同构，客户端可以直接复用同一条落地逻辑：
  /// - 进行中：`{task_id, session_id, status, image_count}`；
  /// - 已完成：额外带 `session`（与 `task_result` 的载荷完全一样）；
  /// - 失败：额外带 `message`；
  /// - 没有任何任务：`{status: "idle"}`。
  ///
  /// 另外始终带上主机当前合集：安卓端在 WS 连不上时，就靠这条把状态行从
  /// 「电脑未连接」改回「已连接 · 合集名」。
  FutureOr<Response> _handleActiveTask(Request request) async {
    final collection = await activeCollection();
    final state = _lastTaskState;
    Map<String, dynamic>? sessionJson;
    String? message;
    if (state != null && state.sessionId != null) {
      final session =
          await repo.getSession(state.sessionId!, includeDeleted: true);
      if (session != null && !session.isDeleted) {
        if (state.status == 'done') sessionJson = await _sessionJson(session);
        if (state.status == 'failed') {
          message = session.errorMessage ?? '分析失败';
        }
      }
    }
    return _json({
      'status': state?.status ?? 'idle',
      'task_id': state?.taskId,
      'session_id': state?.sessionId,
      'image_count': state?.imageCount ?? 0,
      // 主机记下这次状态的时间：客户端用它区分「同一个会话又出了新结果」。
      'updated_at': state?.at ?? 0,
      'message': message,
      'active_collection_id': collection?.collectionId,
      'active_collection_name': collection?.name,
      // 主机**当前的活跃合集列表**（M18 第 4 条）。安卓端把这份列表直接镜像
      // 到本地库（`CoreRepository.mirrorCollections`，只增改不删），于是
      // 「Windows 上新建/改名合集 → 手机历史里那个分组跟着出现」不再依赖
      // `ops_lamport` 这类间接信号：列表本身就是「想要的结果」。
      // 与 `/api/v1/collections` 同构，老客户端忽略这个字段。
      'collections': (await repo.listCollections())
          .map((c) => c.toJson())
          .toList(),
      // 主机本地 ops 的水位（M17 第 5 条）：安卓端每秒轮询时顺带看一眼，
      // 发现涨了就**只拉一次** ops（pull-only），于是 Windows 上改题目等
      // 本地修改在 App 前台时 1 秒内就会落到手机上。纯加法字段，老客户端忽略。
      'ops_lamport': await repo.db.maxLamport(),
      'session': ?sessionJson,
    });
  }

  FutureOr<Response> _handleTaskGet(Request request, String taskId) async {
    final task = await (repo.db.select(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .getSingleOrNull();
    if (task == null) {
      return _error(404, 'not_found', '任务不存在');
    }
    Map<String, dynamic>? sessionJson;
    String? sessionErrorMessage;
    if (task.sessionId != null) {
      final session =
          await repo.getSession(task.sessionId!, includeDeleted: true);
      if (session != null) {
        sessionErrorMessage = session.errorMessage;
        sessionJson = await _sessionJson(session);
      }
    }
    return _json({
      'task_id': task.taskId,
      'status': task.status,
      'session_id': task.sessionId,
      'error_code': task.errorCode,
      // 原来恒为 null：客户端（安卓）显示失败原因时就只能显示空字符串。
      'error_message': sessionErrorMessage,
      'session': ?sessionJson,
    });
  }

  /// 会话 + 题目 + 页序（多页时客户端要显示「N 张图片识别中」）。
  Future<Map<String, dynamic>> _sessionJson(Session session) async {
    final questions = await repo.questionsOfSession(session.sessionId);
    final hashes = await repo.imageHashesOf(session.sessionId);
    return {
      ...session.toJson(),
      'image_hashes': hashes,
      'image_count': hashes.length,
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }

  FutureOr<Response> _handleTaskRetry(Request request, String taskId) async {
    final task = await (repo.db.select(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .getSingleOrNull();
    if (task == null) return _error(404, 'not_found', '任务不存在');
    await executor.retry(taskId);
    return _json({'status': 'queued'});
  }

  /// 「重新生成」（用户需求 7）：安卓端在结果页一键重跑本会话。
  FutureOr<Response> _handleSessionReanalyze(
      Request request, String sessionId) async {
    final session = await repo.getSession(sessionId, includeDeleted: true);
    if (session == null) return _error(404, 'not_found', '会话不存在');
    // 没有页序行（或首图 hash 为空）就没有可重跑的图。原来直接把空列表交给
    // executor，它抛 StateError → 500 且**不是协议 JSON 错误体**，客户端只能显示
    // 「未知错误」。现在提前拦住，按「原图不在主机上」回 409 invalid_request
    // —— 与独立服务端同码同状态（见 spec/09-errors.md §7.1）。
    //
    // 顺带比 executor 更早一步：页图在 `images` 表里**没有行**时也别建任务。
    // 那种任务注定失败（executor 会 `failed/internal/图片文件缺失`），客户端要等
    // 轮询才知道，不如当场给一个能提示用户的协议错误。
    final hashes = await repo.imageHashesOf(sessionId);
    if (hashes.isEmpty || hashes.first.isEmpty) {
      return _error(409, 'invalid_request', '原图已不在电脑上，无法重新识别');
    }
    for (final h in hashes) {
      if (await repo.getImage(h) == null) {
        return _error(409, 'invalid_request', '原图已不在电脑上，无法重新识别');
      }
    }
    final device = await _authDeviceId(request) ?? repo.deviceId;
    final r = await executor.reanalyze(sessionId: sessionId, sourceDevice: device);
    return _json({
      'status': r.status,
      // 任务号必须在响应里：安卓结果页靠它跟踪这次重跑（原来是空串）。
      'task_id': r.taskId,
      'session_id': r.sessionId,
      'question_count': null,
      'cached': false,
    }, status: 202);
  }

  FutureOr<Response> _handleOpsPush(Request request) async {
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
    // M47：op 的**归属**必须等于认证设备。原来只挡「冒充主机」，于是任何已配对
    // 设备都能拿别人的 device_id 配上任意大的 lamport 改写对方的数据
    // （LWW 下高 lamport 必赢），并且会被主机当成真事再同步给所有对端。
    final caller = await _authDeviceId(request);
    for (final raw in rawOps) {
      if (raw is! Map) continue;
      final op = SyncOp.fromJson(Map<String, dynamic>.from(raw));
      // 拒绝「声称由主机自己产生」的 op：主机自己的 op 本来就在本地日志里，
      // 客户端只是在回推拉取过的历史。放行则任何已配对设备都能用高 lamport
      // 冒充主机改写数据（LWW 下高 lamport 必赢）。
      if (op.deviceId == deviceId) continue;
      if (caller == null || op.deviceId != caller) {
        rejected++;
        continue;
      }
      final result = await repo.applyRemoteOp(op);
      if (!result.duplicate) applied++;
    }
    return _json({'applied': applied, 'rejected': rejected});
  }

  FutureOr<Response> _handleOpsPull(Request request) async {
    final fromDevice = request.url.queryParameters['from_device'] ?? '';
    if (fromDevice.isEmpty) {
      return _error(400, 'invalid_request', 'from_device 缺失');
    }
    final since =
        int.tryParse(request.url.queryParameters['since_lamport'] ?? '') ?? 0;
    final cursor =
        int.tryParse(request.url.queryParameters['cursor'] ?? '') ?? since;
    final rows = await repo.db.customSelect(
      'SELECT * FROM sync_ops WHERE device_id = ? AND lamport > ? '
      'ORDER BY lamport ASC LIMIT ?',
      variables: [
        Variable.withString(fromDevice),
        Variable.withInt(cursor),
        Variable.withInt(options.syncPageSize + 1),
      ],
      readsFrom: {repo.db.syncOps},
    ).get();
    final hasMore = rows.length > options.syncPageSize;
    final page = hasMore ? rows.sublist(0, options.syncPageSize) : rows;
    final ops = page
        .map((r) => opFromRow(SyncOpRow(
              opId: r.read<String>('op_id'),
              deviceId: r.read<String>('device_id'),
              lamport: r.read<int>('lamport'),
              entity: r.read<String>('entity'),
              entityId: r.read<String>('entity_id'),
              opType: r.read<String>('op_type'),
              fieldsJson: r.read<String>('fields_json'),
              createdAt: r.read<int>('created_at'),
            )))
        .toList();
    return _json({
      'ops': ops.map((o) => o.toJson()).toList(),
      'has_more': hasMore,
      'next_cursor': page.isEmpty ? null : page.last.read<int>('lamport'),
    });
  }

  /// `GET /api/v1/sync/snapshot`：全量实体的**分页**快照
  /// （`data-model.md` 2.9：返回全量实体（分页））。
  ///
  /// M47：原来一次性 `listSessions(limit: 1000000)` 把整个库读进内存再拼成一个
  /// JSON 字符串 —— 历史一多就是几百 MB。现在按会话分页：`limit`（默认 200，
  /// 上限 1000）+ `offset`；题目 / 页序只带本页涉及的会话，图片只带元数据。
  /// 合集与设备是两张小表，照旧全量（客户端要靠它们补基线）。
  FutureOr<Response> _handleSnapshot(Request request) async {
    final requested =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 200;
    final limit = requested.clamp(1, 1000);
    final offset =
        (int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0)
            .clamp(0, 1 << 30);
    final ids = (await repo.db.customSelect(
      'SELECT session_id FROM sessions WHERE deleted_at IS NULL '
      'ORDER BY created_at ASC, session_id ASC LIMIT ? OFFSET ?',
      variables: [Variable.withInt(limit + 1), Variable.withInt(offset)],
      readsFrom: {repo.db.sessions},
    ).get())
        .map((r) => r.read<String>('session_id'))
        .toList();
    final hasMore = ids.length > limit;
    final pageIds = hasMore ? ids.sublist(0, limit) : ids;
    final sessions = <Session>[];
    final questions = <Map<String, dynamic>>[];
    final sessionImages = <Map<String, dynamic>>[];
    for (final id in pageIds) {
      final s = await repo.getSession(id, includeDeleted: true);
      if (s == null) continue;
      sessions.add(s);
      questions.addAll(
          (await repo.questionsOfSession(id)).map((q) => q.toJson()));
      sessionImages.addAll(
          (await repo.sessionImagesOf(id)).map((p) => p.toJson()));
    }
    final images = <Map<String, dynamic>>[];
    for (final row in await repo.db.select(repo.db.images).get()) {
      // `local_path` 是**本地专属列**（哪台机器上存着这个文件），按 data-model.md
      // 的口径不进同步载荷 —— 快照是「给对端补基线」的同步载荷，把主机的
      // 本地绝对路径发出去既无用、又泄漏主机目录结构。
      images.add(imageFromRow(row).toJson()..remove('local_path'));
    }
    return _json({
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'questions': questions,
      'session_images': sessionImages,
      'collections': (await repo.listCollections())
          .map((c) => c.toJson())
          .toList(),
      'images': images,
      // devices 的 toJson 已排除 token_hash。
      'devices': (await repo.listDevices()).map((d) => d.toJson()).toList(),
      'watermark': await repo.db.maxLamport(),
      'has_more': hasMore,
      'next_offset': hasMore ? offset + pageIds.length : null,
    });
  }

  FutureOr<Response> _handleDevices(Request request) async {
    final devices = await repo.listDevices();
    return _json({'devices': devices.map((d) => d.toJson()).toList()});
  }

  FutureOr<Response> _handleDeviceRevoke(Request request, String id) async {
    await revokeDeviceAndNotify(id);
    return _json({'revoked': id});
  }

  /// 吊销设备并通知对端（HTTP 端点与桌面设置页共用）。
  /// 只改数据库不给手机发通知的话，手机端的 WS 还挂着、界面照旧显示已配对。
  Future<void> revokeDeviceAndNotify(String id) async {
    await repo.revokeDevice(id);
    _broadcast({'type': 'device_revoked', 'device_id': id});
    final ws = _connections.remove(id);
    if (ws != null) {
      _pingTimers.remove(id)?.cancel();
      try {
        await ws.sink.close();
      } catch (_) {
        // 连接已断开。
      }
    }
  }

  // ------------------------------------------------------------
  // WebSocket
  // ------------------------------------------------------------

  FutureOr<Response> _handleWs(Request request) async {
    final authed = await _authDeviceId(request);
    final status = await _authStatus(request);
    if (authed == null) {
      return _error(401, status == AuthStatus.revoked ? 'revoked' : 'unauthorized',
          'WS 握手鉴权失败');
    }
    final deviceId = authed;

    final handler = webSocketHandler((channel, _) {
      _onWsConnected(deviceId, channel);
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

    // hello（含当前合集：用户需求 12，安卓端据此判断能否发起识别）。
    Future(() async {
      final c = await activeCollection();
      _send(channel, {
        'type': 'hello',
        // 必须是**服务端自己**的 device_id：这里原来发的是已鉴权的客户端 id，
        // 任何照协议从 hello 记对端 id 的客户端都会把自己记成主机。
        'server_device_id': this.deviceId,
        'protocol_version': options.protocolVersion,
        'active_collection_id': c?.collectionId,
        'active_collection_name': c?.name,
      });
      // M14 第 6 条：手机正好在主机识别过程中连上来（首次连 / 断线重连）时，
      // 把进行中的本机任务补发一次，否则它会一直停在「没有任务」——
      // 用户看到的就是「Windows 按了热键，安卓端一点反应没有」。
      final pending = _pendingLocalTask;
      if (pending != null) {
        await _emitTaskUpdate(
            pending.sessionId, pending.status, pending.sessionId, pending.imageCount);
      }
    });

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
    }
  }

  Future<void> _onWsData(
      String deviceId, WebSocketChannel channel, Object data) async {
    try {
      final msg = jsonDecode(data.toString());
      if (msg is! Map) return;
      switch (msg['type']) {
        case 'hello':
          final devices = await repo.listDevices();
          for (final d in devices) {
            if (d.deviceId == deviceId) {
              await repo.upsertDevice(d.copyWith(
                  lastSeenAt: now(), appVersion: msg['app_version']?.toString()));
            }
          }
          break;
        case 'ack':
          final watermark = (msg['watermark_lamport'] as num?)?.toInt() ?? 0;
          await _updatePeerState(deviceId, ackedLamport: watermark);
          break;
        case 'push_ops':
          final ops = msg['ops'];
          if (ops is List) {
            var maxLamport = 0;
            for (final raw in ops) {
              if (raw is! Map) continue;
              final op = SyncOp.fromJson(Map<String, dynamic>.from(raw));
              // 同 HTTP：不接受冒充主机自己的 op，也不接受冒充**别的设备**的 op
              // （见 _handleOpsPush）。
              if (op.deviceId == this.deviceId) continue;
              if (op.deviceId != deviceId) continue;
              await repo.applyRemoteOp(op);
              if (op.lamport > maxLamport) maxLamport = op.lamport;
            }
            _send(channel, {'type': 'ack', 'watermark_lamport': maxLamport});
          }
          break;
        case 'pong':
          // 心跳回包。
          break;
      }
    } catch (_) {
      // 无效消息直接忽略。
    }
  }

  Future<void> _updatePeerState(String peerId,
      {required int ackedLamport}) async {
    final existing = await (repo.db.select(repo.db.peerStates)
          ..where((t) => t.peerDeviceId.equals(peerId)))
        .getSingleOrNull();
    if (existing == null) {
      await repo.db.into(repo.db.peerStates).insert(PeerStatesCompanion.insert(
            peerDeviceId: peerId,
            ackedLamport: Value(ackedLamport),
            lastSyncAt: Value(now()),
          ));
    } else if (ackedLamport > existing.ackedLamport) {
      await (repo.db.update(repo.db.peerStates)
            ..where((t) => t.peerDeviceId.equals(peerId)))
          .write(PeerStatesCompanion(
        ackedLamport: Value(ackedLamport),
        lastSyncAt: Value(now()),
      ));
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
  void _broadcast(Object message) {
    for (final channel in _connections.values) {
      _send(channel, message);
    }
  }

  /// 任务状态变化时的外部入口（executor 回调转发到这里）。
  /// done 时额外广播 task_result（含完整会话），failed 时广播 task_failed。
  ///
  /// [imageCount] 是手机端「N 张图片识别中」要显示的页数；传 0 时由会话页序补。
  void notifyTaskUpdate(String taskId, String status, String? sessionId,
      {int imageCount = 0}) {
    // 用户反馈 12：桌面端要能区分「本机截屏」与「手机提交」的任务——
    // 手机发起时要弹到前台显示识别界面，本机截屏时保持后台静默。
    onTaskUpdateHook?.call(status, sessionId);
    unawaited(_emitTaskUpdate(taskId, status, sessionId, imageCount));
  }

  /// 桌面端**本地**截屏（走 AnalysisWorkflow，不经服务端任务队列）的状态广播。
  ///
  /// 修（用户反馈 2）：手机端只会在「自己提交的任务」里看到进度，主机自己截屏
  /// 时手机端什么都不知道 → 「已连接却看不到新记录 / 看不到几张图识别中」。
  /// 本地任务的 task_id 就用 session_id（手机端只把它当刷新信号）。
  ///
  /// 修（用户反馈 M14 第 6 条）：本机截屏必须**保持后台静默** —— 不加这一条时
  /// 它会经过 [notifyTaskUpdate] 从而触发 `onTaskUpdateHook`，让 Windows 主窗口
  /// 在按下识别热键的瞬间自己弹到前台并抢焦点（用户原话：「windows端识别完
  /// windows端会跳出来」）。所以这里只广播，不走那个钩子；
  /// 同时把「进行中」的状态记下来，等手机连上来时补发（见 [_pendingLocalTask]）。
  void notifyLocalSession(String sessionId, String status,
      {int imageCount = 0}) {
    _pendingLocalTask = (status == 'queued' || status == 'analyzing')
        ? _LocalTaskState(sessionId, status, imageCount)
        : null;
    unawaited(_emitTaskUpdate(sessionId, status, sessionId, imageCount));
  }

  Future<void> _emitTaskUpdate(String taskId, String status, String? sessionId,
      int imageCount) async {
    var count = imageCount;
    if (count <= 0 && sessionId != null && sessionId.isNotEmpty) {
      count = (await repo.imageHashesOf(sessionId)).length;
    }
    // 用户反馈 M15 第 4 条：这里是一切任务状态的唯一广播出口，顺手记一份供
    // `GET /api/v1/tasks/active` 只读回放（安卓端的 HTTP 轮询兜底靠它）。
    _lastTaskState = _TaskStateSnapshot(taskId, sessionId, status, count, now());
    _broadcast({
      'type': 'task_update',
      'task_id': taskId,
      'status': status,
      'session_id': ?sessionId,
      'image_count': count,
    });
    if (status == 'done' && sessionId != null) {
      final session = await repo.getSession(sessionId, includeDeleted: true);
      // 墓碑会话没有结果可推（桌面端「同图复用」会把临时会话删掉再报 done，
      // 那种情况下只发状态、不发结果，否则手机会把已删除的记录落进本地库）。
      if (session == null || session.isDeleted) return;
      _broadcast({
        'type': 'task_result',
        'task_id': taskId,
        'session': await _sessionJson(session),
      });
    }
    if (status == 'failed' && sessionId != null) {
      final session = await repo.getSession(sessionId, includeDeleted: true);
      _broadcast({
        'type': 'task_failed',
        'task_id': taskId,
        'error_code': session?.errorCode ?? 'internal',
        'message': session?.errorMessage ?? '分析失败',
      });
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// 进行中的本机截屏任务状态（M14 第 6 条）：手机连上来时用它补发一次。
class _LocalTaskState {
  final String sessionId;
  final String status;
  final int imageCount;

  const _LocalTaskState(this.sessionId, this.status, this.imageCount);
}

/// 主机最近一次广播出去的任务状态（M15 第 4 条）：HTTP 轮询端点的回放依据。
///
/// [sessionId] 可以为 null（任务还没建会话），[at] 是记下这次状态的时间，
/// 客户端用它区分「同一个会话又出了一次新结果」。
class _TaskStateSnapshot {
  final String taskId;
  final String? sessionId;
  final String status;
  final int imageCount;
  final int at;

  const _TaskStateSnapshot(
      this.taskId, this.sessionId, this.status, this.imageCount, this.at);
}
