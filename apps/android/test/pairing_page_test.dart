import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show SectionCard;

import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/ui/pairing_page.dart';

import 'support.dart';

/// 配对页（用户需求 7）：首次进入**不初始化相机、不申请权限**；
/// 点击「开始使用」后才申请相机权限；被拒要有明确提示与重试/去设置的入口；
/// 授权成功后才真正启动扫码。方式二 / 方式三始终可用。
///
/// 用户需求 D2：三个并列模块「方式一：扫码」「方式二：粘贴配对链接」
/// 「方式三：手动输入」；粘贴入口有自己的模块，不再挂在扫码模块里。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;
  late List<String> channelLog;

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
  });

  tearDown(() async {
    clearCaptureChannelMock();
    await db.close();
  });

  /// 扫码视图的假实现：真实的 MobileScanner 在没有设备/模拟器的机器上
  /// 无法创建（平台通道不可用），所以这里注入一个可断言的替身。
  Widget fakeScanner(BuildContext context, ValueChanged<String> onDetected) =>
      ElevatedButton(
        key: const ValueKey('fake-scanner'),
        onPressed: () => onDetected(
            'quizsync://pair?host=1.2.3.4&port=8765&code=123456'),
        child: const Text('SCANNER'),
      );

  Future<void> pumpPairing(WidgetTester tester) async {
    await tester.pumpWidget(wrapApp(
      app,
      home: PairingPage(app: app, scannerBuilder: fakeScanner),
    ));
    await tester.pump();
  }

  /// 找到包含某个 key 的那个 [SectionCard] 模块标题。
  String moduleTitleOf(WidgetTester tester, Key key) {
    final card = tester.widget<SectionCard>(find.ancestor(
      of: find.byKey(key),
      matching: find.byType(SectionCard),
    ));
    return card.title;
  }

  testWidgets('首次进入：不申请相机权限、不创建扫码视图，先给说明与按钮', (tester) async {
    channelLog = installCaptureChannelMock();
    await pumpPairing(tester);

    // 说明 + 「开始使用」按钮；方式二 / 方式三的既有入口都在。
    expect(find.byKey(const ValueKey('start-scan')), findsOneWidget);
    expect(find.text('开始使用（扫码配对）'), findsOneWidget);
    expect(find.textContaining('点击下面的按钮才会申请相机权限'), findsOneWidget);
    expect(find.text('方式一：扫码'), findsOneWidget);
    expect(find.text('方式二：粘贴配对链接'), findsOneWidget);
    expect(find.text('方式三：手动输入'), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-pair-link')), findsOneWidget);
    // 用户需求 D2：粘贴入口属于「方式二」模块，不在「方式一：扫码」里。
    expect(moduleTitleOf(tester, const ValueKey('paste-pair-link')),
        '方式二：粘贴配对链接');
    expect(moduleTitleOf(tester, const ValueKey('start-scan')), '方式一：扫码');

    // M46 第 5 条：这句引导文案原来指向 Windows 端已经不存在的分类
    // 「服务（Android 配对）」；Windows 那边现在叫「连接设备」，文案必须跟着改。
    expect(find.textContaining('设置 → 连接设备'), findsOneWidget,
        reason: '配对引导要指向 Windows 端真实存在的「连接设备」分类');
    expect(find.textContaining('服务（Android 配对）'), findsNothing,
        reason: '过时文案必须删干净');

    // 关键断言：一次都没碰相机。
    expect(channelLog, isNot(contains('requestCameraPermission')));
    expect(find.byKey(const ValueKey('fake-scanner')), findsNothing);
  });

  testWidgets('点击「开始使用」：先申请相机权限，授权成功后启动扫码', (tester) async {
    channelLog = installCaptureChannelMock(cameraGranted: true);
    await pumpPairing(tester);

    await tester.tap(find.byKey(const ValueKey('start-scan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(channelLog, contains('requestCameraPermission'));
    expect(find.byKey(const ValueKey('fake-scanner')), findsOneWidget,
        reason: '授权成功后才创建扫码视图');
    expect(find.byKey(const ValueKey('start-scan')), findsNothing);
    expect(find.byKey(const ValueKey('camera-denied')), findsNothing);
  });

  testWidgets('相机权限被拒：明确提示 + 重试/去设置入口，且不启动扫码', (tester) async {
    channelLog = installCaptureChannelMock(cameraGranted: false);
    await pumpPairing(tester);

    await tester.tap(find.byKey(const ValueKey('start-scan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('camera-denied')), findsOneWidget);
    expect(find.textContaining('相机权限未授予'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-scan-permission')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-camera-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-scanner')), findsNothing,
        reason: '没授权就不能启动扫码');
    // 被拒时方式二 / 方式三仍然可用。
    expect(find.text('方式二：粘贴配对链接'), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-pair-link')), findsOneWidget);
    expect(find.text('方式三：手动输入'), findsOneWidget);

    // 重试：这次系统同意授权 → 立刻启动扫码。
    installCaptureChannelMock(cameraGranted: true);
    await tester.tap(find.byKey(const ValueKey('retry-scan-permission')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('fake-scanner')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-denied')), findsNothing);
  });
}
