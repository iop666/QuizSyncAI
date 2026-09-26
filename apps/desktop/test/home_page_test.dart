import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/ui/home_page.dart';

/// 主界面（M8 界面优化）的结构与点击入口回归测试。
/// 重点锁定：失败会话**必须**有「框选题目区域后重试」按钮
/// （旧实现拿了 onCropRetry 却没有任何按钮，这个入口在界面上点不到）。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
  });

  tearDown(() async => db.close());

  /// 挂载主界面并等异步数据落地。
  /// 每个用例结束都换成空树：drift 的流查询 / Riverpod autoDispose 会留下
  /// 一个零延迟 Timer，不清理会被测试框架判为「dispose 后仍有 pending timer」。
  Future<void> pumpHome(WidgetTester tester,
      {Future<void> Function()? onCapture,
      Size size = const Size(1200, 800)}) async {
    // 用接近真实窗口的尺寸；另有专门用例测最小窗口 860x520 的窄布局不溢出。
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => SettingsController(
              MemoryKeyValueStore(),
            )..load()),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        dataRootProvider.overrideWithValue(Directory.systemTemp.path),
        apiKeyReaderProvider.overrideWithValue(() async => null),
      ],
      child: MaterialApp(
        theme: QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A),
        home: HomePage(onCapture: onCapture),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 卸载界面：drift 流查询/Riverpod 会留下零延迟 Timer，必须在用例体内清掉
  /// （框架的 pending-timer 断言在 tearDown 之前执行）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> addSession(String id, TaskState status,
      {String? errorCode, String? errorMessage, int questionCount = 0}) async {
    await repo.upsertSession(Session(
      sessionId: id,
      imageHash: 'h-$id',
      sourceDevice: 'windows-local',
      status: status,
      errorCode: errorCode,
      errorMessage: errorMessage,
      questionCount: questionCount,
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
  }

  testWidgets('空状态：给出热键提示与「立即截屏搜题」入口', (tester) async {
    await pumpHome(tester, onCapture: () async {});

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('准备好搜题了'), findsOneWidget);
    expect(find.text('立即截屏搜题'), findsOneWidget);
    expect(find.text('打开设置'), findsOneWidget);
    // M21 第 2 条：这里原来断言顶栏药丸的「服务未启动」——药丸已按用户要求删除，
    // 该断言随之移除（空状态自身的四项断言一条没动）。
    // 免责声明常驻（SPEC 4.4）
    expect(find.text('答案由 AI 生成，仅供参考'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('用户反馈 8：标题「QuizSync AI」前面是应用自己的图标', (tester) async {
    await pumpHome(tester, onCapture: () async {});

    // 位置：图标必须在标题左侧（原来的自绘渐变方块换成了应用图标）。
    final logo = find.byKey(const ValueKey('app-title-logo'));
    final title = find.text('QuizSync AI');
    expect(logo, findsOneWidget, reason: '主界面标题前必须有品牌图标');
    expect(tester.getCenter(logo).dx, lessThan(tester.getCenter(title).dx));

    // 内容：就是关于页/任务栏用的那一枚 assets/app_icon.png，不是另画的图形。
    final image = tester.widget<Image>(find.byKey(
        const ValueKey('app-title-logo-image')));
    expect((image.image as AssetImage).assetName, 'assets/app_icon.png');

    // 尺寸固定且正方形：图片不会被拉变形。
    final size = tester.getSize(logo);
    expect(size.width, size.height);
    expect(size.width, greaterThan(12));

    // 资源真的能加载（flutter test 会按 pubspec 打出资源包）。
    final bytes = await rootBundle.load('assets/app_icon.png');
    expect(bytes.lengthInBytes, greaterThan(0));
    await unmount(tester);
  });

  testWidgets('失败会话：错误原因 + 「框选题目区域后重试」按钮真的存在', (tester) async {
    await addSession('s-fail', TaskState.failed,
        errorCode: 'no_question_found', errorMessage: '未识别到题目');
    await pumpHome(tester);

    expect(find.text('识别失败'), findsOneWidget);
    expect(find.text('重新分析'), findsOneWidget);
    // 这条断言就是本次修复的核心：以前这个按钮根本不存在。
    expect(find.text('框选题目区域后重试'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('成功的会话：题目卡片 + 底部导航 + 会话头信息', (tester) async {
    await addSession('s-done', TaskState.done, questionCount: 1);
    await repo.upsertQuestion(Question(
      questionId: 'q1',
      sessionId: 's-done',
      ordinal: 0,
      questionNo: '3',
      stem: '测试题干',
      type: QuestionType.single,
      options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
      choice: const ['B'],
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
    await pumpHome(tester);

    expect(find.byType(QuestionCard), findsOneWidget);
    expect(find.text('测试题干'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-prev')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-back-latest')), findsOneWidget);
    expect(find.textContaining('识别出 1 道题'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('分析中：显示已耗时与取消按钮', (tester) async {
    await addSession('s-run', TaskState.analyzing);
    await pumpHome(tester);

    expect(find.text('正在识别题目…'), findsOneWidget);
    expect(find.textContaining('已耗时'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('点«删除本次»会先弹确认框（避免误删）', (tester) async {
    await addSession('s-del', TaskState.done, questionCount: 1);
    await pumpHome(tester);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除这条记录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(await repo.getSession('s-del'), isNotNull, reason: '取消后记录仍在');
    await unmount(tester);
  });

  testWidgets('最小窗口尺寸（860x520）不溢出：工具按钮收进「更多」菜单', (tester) async {
    await addSession('s-min', TaskState.done, questionCount: 2);
    await repo.upsertQuestion(Question(
      questionId: 'q-min',
      sessionId: 's-min',
      ordinal: 0,
      stem: '很窄的窗口也要能看',
      type: QuestionType.blank,
      answerText: '可以',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
    await pumpHome(tester, size: const Size(860, 520));

    // 溢出会以异常形式抛出（黄黑条 + RenderFlex overflowed）。
    expect(tester.takeException(), isNull, reason: '窄窗口不得出现布局溢出');
    // 窄布局下四个动作收进「更多」。
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byType(QuestionCard), findsOneWidget);
    await unmount(tester);
  });

  // M19 第 1 条曾在这里放顶栏「配对状态药丸」的 5 条纯函数断言 + 3 条 widget
  // 断言；**M21 第 2 条按用户要求把药丸整个删掉**（「删除掉『未配对』和已配对
  // 那个药丸显示」），代码与对应用例一并移除 —— 删的是被取消的功能的断言，
  // 不是为了跑绿而放宽任何断言。已配对设备仍逐台列在「设置 → 连接设备」里。
}
