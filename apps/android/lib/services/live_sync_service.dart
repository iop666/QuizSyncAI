import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../state/app_state.dart';

/// 造 WS 客户端的工厂。[deviceId] 来自本地库，所以不能做成无参构造。
typedef SyncSocketFactory = SyncSocket Function(
    PairingInfo pairing, String deviceId);

/// WS 长连接生命周期（用户需求 7：主机开始识别后自动加载）。
///
/// 只做「连上 / 断了重连 / 把消息转给 LiveUpdates」，
/// 消息语义与本地库写入都在 [LiveUpdates]（可单测）。
class LiveSyncService {
  LiveSyncService({
    required this.app,
    required this.onMessage,
    this.onReconnected,
    SyncSocketFactory? socketFactory,
  }) : _socketFactory = socketFactory ?? _defaultSocketFactory;

  final AndroidAppState app;
  final Future<void> Function(Map<String, dynamic> message) onMessage;

  /// 每次**连上**（首次连上也算）时回调（M14 第 6 条）。
  ///
  /// `SyncSocket` 的重连只保证「连接恢复」，断线窗口里主机推过来的
  /// `task_update` / `task_result` 不会重发，必须由宿主补拉一次，
  /// 否则用户看到的是「Windows 截屏识别了，安卓端毫无反应」。
  final Future<void> Function()? onReconnected;

  /// 测试注入点：本机没有主机可连，真实 WS 建不起来。
  final SyncSocketFactory _socketFactory;

  SyncSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  /// 连接状态订阅必须存成字段：`stop()` 不取消它的话，重新配对后旧 socket
  /// 的事件还会触发补拉（重复同步）。
  StreamSubscription<bool>? _connSub;

  bool get connected => _socket?.isConnected ?? false;

  static SyncSocket _defaultSocketFactory(
          PairingInfo pairing, String deviceId) =>
      SyncSocket(
        wsUri: Uri.parse('ws://${pairing.host}:${pairing.port}/ws'),
        token: pairing.token,
        deviceId: deviceId,
      );

  void start(PairingInfo pairing) {
    stop();
    final socket = _socketFactory(pairing, app.repo.deviceId);
    _socket = socket;
    _sub = socket.messages.listen((msg) {
      unawaited(onMessage(msg));
    });
    // 先订阅、后 connect：否则首次连上的 true 会在订阅之前发出来。
    _connSub = socket.connectionState.listen((up) {
      if (up) unawaited(onReconnected?.call());
    });
    unawaited(socket.connect());
  }

  void stop() {
    final connSub = _connSub;
    _connSub = null;
    unawaited(connSub?.cancel());
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.dispose());
  }

  @visibleForTesting
  SyncSocket? get socket => _socket;
}
