import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// WS 客户端（protocol.md 第 4 节）：
/// 握手鉴权（Bearer 头 + X-QS-Device-Id）、10s 内回 pong、
/// 指数退避重连 1/2/5/10/30s（上限 30s）、收到 device_revoked 清理退出。
/// 「先拉后推」的补齐由调用方结合 ApiClient 完成。
class SyncSocket {
  final Uri wsUri;
  final String token;
  final String deviceId;
  final String appVersion;
  final Duration pingInterval;
  final Duration pongTimeout;
  final Duration Function(int attempt) backoff;

  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _checkTimer;
  int _attempt = 0;
  bool _closedByUser = false;
  int _lastServerPingAt = 0;

  IOWebSocketChannel? get channel => _channel;
  bool get isConnected => _channel != null;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _connectionController = StreamController<bool>.broadcast();

  /// 握手被拒（401 revoked/unauthorized）时置 true 并停止重连。
  /// protocol.md 4.1：这种情况应退化为轮询并提示重新配对，而不是无限重连。
  bool authFailed = false;
  Stream<bool> get connectionState => _connectionController.stream;

  SyncSocket({
    required this.wsUri,
    required this.token,
    required this.deviceId,
    this.appVersion = '1.0.0',
    this.pingInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 10),
    Duration Function(int attempt)? backoff,
  }) : backoff = backoff ?? _defaultBackoff;

  static Duration _defaultBackoff(int attempt) {
    const schedule = [1, 2, 5, 10, 30];
    return Duration(seconds: schedule[attempt.clamp(0, schedule.length - 1)]);
  }

  /// 从握手失败的异常里挖出 HTTP 状态码（web_socket_channel 把它包在
  /// WebSocketChannelException 的 message 里，形如 "HTTP 401"）。
  static int _handshakeStatus(Object e) {
    final text = e.toString();
    final m = RegExp(r'\b(4\d\d|5\d\d)\b').firstMatch(text);
    return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
  }

  Future<void> connect() async {
    if (_closedByUser) return;
    final channel = IOWebSocketChannel.connect(
      wsUri,
      headers: {
        'Authorization': 'Bearer $token',
        'X-QS-Device-Id': deviceId,
        'X-QS-Client-Version': appVersion,
      },
      pingInterval: const Duration(seconds: 20),
    );
    _channel = channel;
    try {
      await channel.ready;
    } catch (e) {
      // 区分「连不上」与「被拒绝」：401/403 说明 token 已失效/被吊销，
      // 重连多少次都没用——标记 authFailed 并停手，让调用方转轮询并提示
      // 重新配对（原来这里是静默无限重连，用户永远等不到结果）。
      final status = _handshakeStatus(e);
      if (status == 401 || status == 403) {
        authFailed = true;
        _closedByUser = true;
        _cleanup();
        _connectionController.add(false);
        _messageController.add({
          'type': 'auth_failed',
          'status': status,
        });
        return;
      }
      _scheduleReconnect();
      return;
    }
    _attempt = 0;
    _lastServerPingAt = nowMs();
    _connectionController.add(true);

    // 客户端 hello（protocol.md 4.3）。
    _send({
      'type': 'hello',
      'device_id': deviceId,
      'app_version': appVersion,
      'platform': 'android',
    });

    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final silentFor = nowMs() - _lastServerPingAt;
      if (silentFor > pingInterval.inMilliseconds + pongTimeout.inMilliseconds) {
        // 服务端 ping 停了：连接已死，强制重连。
        _channel?.sink.close().catchError((_) {});
      }
    });

    _sub = channel.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data.toString());
          if (msg is Map<String, dynamic>) {
            if (msg['type'] == 'ping') {
              _lastServerPingAt = nowMs();
              _send({'type': 'pong', 'ts': msg['ts']});
            }
            if (msg['type'] == 'device_revoked' && msg['device_id'] == deviceId) {
              // 收到吊销：断开（调用方负责清 token 并提示重新配对，SPEC §8）。
              _closedByUser = true;
              unawaited(close());
            }
            _messageController.add(msg);
          }
        } catch (_) {}
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_closedByUser || authFailed) return;
    _cleanup();
    _connectionController.add(false);
    final wait = backoff(_attempt++);
    Timer(wait, () => unawaited(connect()));
  }

  void _cleanup() {
    _sub?.cancel();
    _sub = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _channel = null;
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  /// ack：上报已收到的最大 lamport（含来源设备）。
  void sendAck(int watermarkLamport, String watermarkDevice) {
    _send({
      'type': 'ack',
      'watermark_lamport': watermarkLamport,
      'watermark_device': watermarkDevice,
    });
  }

  /// 推送本地待发 ops。
  void sendPushOps(List<SyncOp> ops) {
    _send({'type': 'push_ops', 'ops': ops.map((o) => o.toJson()).toList()});
  }

  Future<void> close() async {
    _closedByUser = true;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _cleanup();
  }

  Future<void> dispose() async {
    await close();
    await _messageController.close();
    await _connectionController.close();
  }
}
