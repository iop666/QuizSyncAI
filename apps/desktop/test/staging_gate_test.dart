import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/screen_capture.dart';
import 'package:quizsync_desktop/state/analysis_workflow.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/state/capture_coordinator.dart';

/// 假截屏：固定返回一张 8×8 的非黑帧（单测里没有 GDI 环境，不碰真实屏幕）。
/// 每次调用换一点颜色，好让「两次识别」算出**不同**的图片哈希 —— 哈希相同会
/// 走分析缓存，就测不出「到底调了几次 AI」。
class _FakeCapture extends ScreenCaptureService {
  int shots = 0;

  @override
  CapturedScreen captureCursorMonitor() {
    shots++;
    final seed = shots * 37;
    final px = Uint8List(8 * 8 * 4);
    for (var i = 0; i < px.length; i += 4) {
      px[i] = (0x20 + seed) & 0xFF;
      px[i + 1] = (0x80 + seed) & 0xFF;
      px[i + 2] = (0x40 + seed) & 0xFF;
      px[i + 3] = 0xFF;
    }
    return CapturedScreen(width: 8, height: 8, bgra: px);
  }

  @override
  T hideWindowWhile<T>(T Function() action,
          {Duration settle = const Duration(milliseconds: 180)}) =>
      action();
}

/// M47：「结束多页并识别」这条入口原来**两个前置检查都不做**（热键单张、多页、
/// 剪贴板、拖入粘贴四条都做）——用户把当前合集删掉之后按 F8 收尾，照样会调用
/// AI 花钱、并把记录落成「未分类」。这里把闸门钉住：
/// 前置条件不满足时**既不调 AI，也不清空暂存区**（已抓的页面留着）。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late SettingsController settings;
  late FakeAiProvider provider;
  late CaptureCoordinator coordinator;
  late WidgetRef capturedRef;
  late BuildContext capturedContext;
  late Directory imageDir;

  const device = 'windows-local';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: device);
    await repo.init();
    settings = SettingsController(MemoryKeyValueStore());
    await settings.load();
    // 真图片目录：识别链路会往这里写 jpg（别用仓库里的相对路径，会把测试产物
    // 留在 apps/desktop/ 下）。
    imageDir = await Directory.systemTemp.createTemp('m47-staging-');
    provider = FakeAiProvider(File(
            '../../packages/quizsync_core/test/fixtures/multi_and_judge.json')
        .absolute
        .path);
  });

  tearDown(() async {
    await db.close();
    await imageDir.delete(recursive: true);
  });

  AnalysisWorkflow mkWorkflow() => AnalysisWorkflow(
        repo: repo,
        engine: AnalysisEngine(
          provider: provider,
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: device,
        ),
        deviceId: device,
      );

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => settings),
        workflowProvider.overrideWithValue(mkWorkflow()),
        apiKeyReaderProvider.overrideWithValue(() async => 'test-key'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          }),
        ),
      ),
    ));
    await tester.pump();
    coordinator = CaptureCoordinator(
      refOf: () => capturedRef,
      contextOf: () => capturedContext,
      capture: _FakeCapture(),
      imageDir: imageDir.path,
    );
  }

  testWidgets('结束多页也要过合集闸门：没合集时不调 AI、暂存页不丢', (tester) async {
    await tester.runAsync(() async {
      await repo.upsertCollection(Collection(
        collectionId: 'c-1',
        name: '合集甲',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: device,
      ));
      await repo.setSetting(kActiveCollectionKey, 'c-1');
    });

    await pumpHost(tester);
    // 识别链路里有真实文件 IO（fixture 与图片目录），必须走 runAsync，
    // 否则在 flutter_test 的假异步环境里永远不会完成。
    await tester.runAsync(() async {
      await coordinator.multipageCapture();
      await coordinator.multipageCapture();
    });
    expect(coordinator.stagedCount, 2, reason: '两页都进了暂存区');

    // 用户把当前合集删掉（删合集会把「当前合集」置空）。
    await tester.runAsync(() async {
      await repo.setSetting(kActiveCollectionKey, '');
      await coordinator.submitStaged();
    });
    expect(provider.callCount, 0, reason: '没有合集时不得调用 AI');
    expect(await db.select(db.sessions).get(), isEmpty,
        reason: '不得产生「未分类」记录');
    expect(coordinator.stagedCount, 2, reason: '前置条件不满足时不能把已抓的页丢掉');

    // 选回合集再按一次：这次真的上传，两页仍然一起送。
    await tester.runAsync(() async {
      await repo.setSetting(kActiveCollectionKey, 'c-1');
      await coordinator.submitStaged();
    });
    expect(provider.callCount, 1);
    expect(provider.lastImageCount, 2);
    expect(coordinator.stagedCount, 0);
    final sessions = await db.select(db.sessions).get();
    expect(sessions.single.collectionId, 'c-1');
    await tester.pump(const Duration(seconds: 4)); // 放掉 SnackBar 计时器
  });

  testWidgets('正常路径不受影响：有合集+有 Key 时暂存区照旧被消费', (tester) async {
    await tester.runAsync(() async {
      await repo.upsertCollection(Collection(
        collectionId: 'c-2',
        name: '合集乙',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: device,
      ));
      await repo.setSetting(kActiveCollectionKey, 'c-2');
    });

    await pumpHost(tester);
    await tester.runAsync(() async {
      await coordinator.multipageCapture();
      await coordinator.submitStaged();
    });
    expect(provider.callCount, 1);
    expect(coordinator.stagedCount, 0);
    expect(coordinator.busy, isFalse);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('连按两次截屏识别只调一次 AI（闸门必须同步置位）', (tester) async {
    await tester.runAsync(() async {
      await repo.upsertCollection(Collection(
        collectionId: 'c-3',
        name: '合集丙',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: device,
      ));
      await repo.setSetting(kActiveCollectionKey, 'c-3');
    });

    await pumpHost(tester);
    await tester.runAsync(() async {
      // 两次触发都排在同一拍里（模拟连按 F8）：修复前两次都能通过 `if (_busy)`，
      // 各自截一张图、各自问一次 AI。
      final first = coordinator.captureAndAnalyze();
      final second = coordinator.captureAndAnalyze();
      await Future.wait([first, second]);
    });
    expect(provider.callCount, 1, reason: '第二次必须被闸门挡住');
    expect(await db.select(db.sessions).get(), hasLength(1));
    expect(coordinator.busy, isFalse);
    await tester.pump(const Duration(seconds: 4));
  });
}
