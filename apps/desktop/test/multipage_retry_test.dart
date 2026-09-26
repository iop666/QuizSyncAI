import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_desktop/state/analysis_workflow.dart';

/// 用户需求 4/6：多页会话的「重新分析」必须读回**全部**页；
/// 任何一页的本机文件不在了，要抛出带明确文案的 [StateError]，
/// UI 层原样显示（不能吞掉，否则用户只看到「点了没反应」）。
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

  AnalysisWorkflow mkWorkflow(FakeAiProvider provider) => AnalysisWorkflow(
        repo: repo,
        engine: AnalysisEngine(
          provider: provider,
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: 'windows-local',
        ),
        deviceId: 'windows-local',
      );

  Future<void> mkMultiPageSession(String sessionId) async {
    await repo.upsertSession(Session(
      sessionId: sessionId,
      collectionId: 'c-multi',
      imageHash: 'p1',
      sourceDevice: 'windows-local',
      status: TaskState.failed,
      errorCode: 'ai_timeout',
      createdAt: nowMs(),
      updatedAt: nowMs(),
      updatedBy: 'windows-local',
    ));
    await repo.setSessionImages(sessionId, ['p1', 'p2', 'p3']);
  }

  test('多页重新分析：本机缺第 2 页 → StateError 文案明确指出是第几页', () async {
    await mkMultiPageSession('s-missing');
    final workflow = mkWorkflow(FakeAiProvider(
        File('../../packages/quizsync_core/test/fixtures/single_choice.json')
            .absolute
            .path));
    // 只有首页（调用方已经加载过）在，其余页的本机文件都读不到。
    workflow.readImageFile = (hash) async => null;

    await expectLater(
      workflow.retrySession(
        sessionId: 's-missing',
        jpeg: Uint8List.fromList([1, 2, 3]),
        config: const AiConfig(model: 'test-model'),
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message',
          contains('第 2 页图片文件已不在本机'))),
    );
  });

  test('多页重新分析：三页都读得回来 → 一次 AI 调用带 3 张图并出结果', () async {
    await mkMultiPageSession('s-all-pages');
    final provider = FakeAiProvider(
        File('../../packages/quizsync_core/test/fixtures/single_choice.json')
            .absolute
            .path);
    final workflow = mkWorkflow(provider);
    workflow.readImageFile = (hash) async => Uint8List.fromList([hash.length]);

    final result = await workflow.retrySession(
      sessionId: 's-all-pages',
      jpeg: Uint8List.fromList([1, 2, 3]),
      config: const AiConfig(model: 'test-model'),
    );

    expect(result.ok, isTrue);
    expect(result.sessionId, 's-all-pages', reason: '重试复用同一会话');
    expect(provider.callCount, 1);
    expect(provider.lastImageCount, 3, reason: '三页必须一次发给 AI，而不是只发首页');
    expect((await repo.questionsOfSession('s-all-pages')), isNotEmpty);
  });
}
