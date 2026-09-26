import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/services/live_sync_service.dart';
import 'package:quizsync_android/state/app_state.dart';

import 'support.dart';

/// M14 第 6 条：Windows 本机截屏识别时安卓端「一点反应没有」的根因是
/// WS 断线窗口里漏掉的推送没人补拉。`SyncSocket` 的重连只恢复连接，
/// 这里断言「重连成功 → 通知宿主补齐」这条链路。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;

  const pairing = PairingInfo(
    host: '127.0.0.1',
    port: 8765,
    token: 't',
    serverDeviceId: 'server-1',
    serverName: '测试电脑',
  );

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
  });

  tearDown(() async => db.close());

  test('socket 报「已连接」时回调 onReconnected（每次重连都要补一次）', () async {
    final socket = FakeSyncSocket();
    var restored = 0;
    final service = LiveSyncService(
      app: app,
      onMessage: (_) async {},
      onReconnected: () async => restored++,
      // 本机没有主机可连：真实 WS 建不起来，注入假 socket 驱动状态流。
      socketFactory: (_, _) => socket,
    );

    service.start(pairing);
    await flushPending();
    expect(restored, 0, reason: '还没连上，不该补拉');

    socket.report(true); // 首次连上
    await flushPending();
    expect(restored, 1);

    socket.report(false); // 掉线
    await flushPending();
    expect(restored, 1, reason: '断开本身不是补齐时机');

    socket.report(true); // 重连成功
    await flushPending();
    expect(restored, 2, reason: '重连成功必须补拉断线期间的推送');

    // stop() 必须取消连接状态订阅：否则重新配对后旧 socket 的事件
    // 还会触发补拉（重复同步）。
    service.stop();
    await flushPending();
    socket.report(true);
    await flushPending();
    expect(restored, 2, reason: 'stop() 之后不再监听旧 socket');
  });
}

/// 假 WS 客户端：只提供 [connectionState] 与 [messages] 两条流，
/// 由测试自己喂状态。
class FakeSyncSocket extends SyncSocket {
  FakeSyncSocket()
      : super(
          wsUri: Uri.parse('ws://127.0.0.1:1/ws'),
          token: 't',
          deviceId: 'android-local',
        );

  final _states = StreamController<bool>.broadcast();
  final _messages = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<bool> get connectionState => _states.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> connect() async {}

  /// 模拟一次「连接成功 / 断开」。dispose 之后调用是安全的空操作。
  void report(bool up) {
    if (!_states.isClosed) _states.add(up);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _messages.close();
    await super.dispose();
  }
}

/// 让已经排队的微任务跑完（onReconnected 是 unawaited 调用的）。
Future<void> flushPending() => Future<void>.delayed(Duration.zero);
