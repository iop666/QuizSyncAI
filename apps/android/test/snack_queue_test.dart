import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/ui/home_page.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'support.dart';

/// M49 第 2 条（用户反馈）：识别期间攒下的提示，回到应用后一个一个跳出来。
///
/// `ScaffoldMessenger` 的队列是「一条 4 秒」串行播放：悬浮球手势期间 App 在后台
/// （用户正在别的应用里看题），每条提示都进队 → 回来要连着看十几秒。
/// 修复后的规则：**后台不入队**（后台由 `AndroidCaptureController._notify` 用
/// 系统 Toast 提示）、**前台只留最新一条**、**回前台清掉积压**。
///
/// 断言口径：提示「跳完没有」。同一句话重复出现时按文字断言分不出新旧，所以
/// 连发多条后推进 5 秒（SnackBar 默认 4 秒）——队列被清掉的话屏幕上就该空了。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
    installCaptureChannelMock();
  });

  tearDown(() async {
    clearCaptureChannelMock();
    await db.close();
  });

  /// 模拟悬浮球手势（Kotlin → Dart 的 `ball_action`）。
  ///
  /// 未配对时每条都会得到「请先与 Windows 端配对」—— 这句话本身不是重点，
  /// 重点是**它进了几次队列**。
  Future<void> ballAction(String action) async {
    final data = const StandardMethodCodec()
        .encodeMethodCall(MethodCall('ball_action', action));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('quizsync/capture', data, (_) {});
  }

  /// 模拟系统生命周期消息（`handleAppLifecycleStateChanged` 是 @protected，
  /// 测试里走官方的 `flutter/lifecycle` 通道）。
  Future<void> setLifecycle(AppLifecycleState state) async {
    final message = const StringCodec().encodeMessage(state.toString());
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('flutter/lifecycle', message, (_) {});
  }

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(wrapApp(
      app,
      home: const AndroidHomePage(pairing: null),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('前台连发三条提示：屏幕上只有一条，且看完就结束（不再排队回放）',
      (tester) async {
    await pumpHome(tester);
    expect(find.byType(SnackBar), findsNothing, reason: '挂载时没有提示');

    for (var i = 0; i < 3; i++) {
      await ballAction('capture');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget, reason: '该提示的时候要提示');
    expect(find.textContaining('请先与 Windows 端配对'), findsOneWidget);

    // 4 秒后第一条自己消失；积压的提示被丢掉 → 屏幕应该是空的。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing,
        reason: 'M49：旧提示不排队，看完一条就结束');

    await unmount(tester);
  });

  testWidgets('后台产生的提示不入队，回到前台也不会逐条跳出来', (tester) async {
    await pumpHome(tester);

    // 用户正在别的应用里看题（悬浮球手势期间的真实状态）。
    await setLifecycle(AppLifecycleState.paused);
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await ballAction('capture_long');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 注意：挂起状态下框架不出帧，这一条查的是「这一刻屏幕上没有」；
    // 真正判定「有没有入队」的是下面回前台那一刻（负向对照就是死在那条上）。
    expect(find.byType(SnackBar), findsNothing);

    await setLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing,
        reason: 'M49：回到前台不再把攒下的提示一个一个跳出来（后台的提示由系统 Toast 负责）');

    // 回到前台后该提示的照常提示（别把提示整体关掉了）。
    await ballAction('capture');
    await tester.pumpAndSettle();
    expect(find.textContaining('请先与 Windows 端配对'), findsOneWidget);

    await unmount(tester);
  });
}
