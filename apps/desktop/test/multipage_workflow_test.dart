import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_desktop/state/analysis_workflow.dart';

/// 用户需求 4/8：多页识别作为**一次**识别落库，并归属当前合集。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  const device = 'windows-local';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: device);
    await repo.init();
  });

  tearDown(() async => db.close());

  AnalysisWorkflow mkWorkflow(FakeAiProvider provider) => AnalysisWorkflow(
        repo: repo,
        engine: AnalysisEngine(
          provider: provider,
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: device,
        ),
        deviceId: device,
      );

  const config = AiConfig(model: 'test-model');

  String fixturePath(String name) =>
      File('../../packages/quizsync_core/test/fixtures/$name').absolute.path;

  WorkflowPage page(String hash, int seed) => WorkflowPage(
        jpeg: Uint8List.fromList([seed, seed, seed]),
        width: 1600,
        height: 900,
        hash: hash,
      );

  test('多页：一次请求送全部页，会话记页序与合集，题号/不全标记齐全', () async {
    final collection = await repo.upsertCollection(Collection(
      collectionId: 'c-1',
      name: '期末复习',
      createdAt: 1,
      updatedAt: 1,
      updatedBy: device,
    ));
    await repo.setSetting(kActiveCollectionKey, collection.collectionId);

    final provider = FakeAiProvider(fixturePath('incomplete_questions.json'));
    final workflow = mkWorkflow(provider);

    final result = await workflow.runMulti(
      pages: [page('p1', 1), page('p2', 2), page('p3', 3)],
      config: config,
    );
    expect(result.ok, isTrue);
    expect(provider.lastImageCount, 3, reason: '三页必须同一次请求送出');

    final session = (await repo.getSession(result.sessionId))!;
    expect(session.status, TaskState.done);
    expect(session.collectionId, 'c-1', reason: '落在当前选中的合集里');
    expect(session.imageHash, 'p1', reason: 'sessions.image_hash = 第一页');
    expect(await repo.imageHashesOf(result.sessionId), ['p1', 'p2', 'p3']);
    expect(session.questionCount, 2, reason: '只有答案的条目被丢弃');

    final questions = await repo.questionsOfSession(result.sessionId);
    expect(questions[0].incomplete, isTrue);
    expect(questions[0].answerGuessed, isTrue);
    expect(questions[0].displayTitle, '1. 第 12 题');
    expect(questions[1].incomplete, isFalse);
    expect(questions[1].answerGuessed, isFalse);

    // 三张图都入库，且都能读到页序
    for (final h in ['p1', 'p2', 'p3']) {
      expect(await repo.getImage(h), isNotNull);
    }
    // 每张图各有 upsert op，会话 1 条 + 页 3 条 + 题目 2 条
    final ops = await db.select(db.syncOps).get();
    expect(ops.where((o) => o.entity == 'session_image').length, 3);
    expect(ops.where((o) => o.entity == 'session').length, greaterThanOrEqualTo(1));
  });

  test('单页 run() 仍走同一条多页通道', () async {
    final provider = FakeAiProvider(fixturePath('multi_and_judge.json'));
    final workflow = mkWorkflow(provider);
    final result = await workflow.run(
      jpeg: Uint8List.fromList([9, 9, 9]),
      imageHash: 'single-h',
      width: 100,
      height: 100,
      config: config,
    );
    expect(result.ok, isTrue);
    expect(provider.lastImageCount, 1);
    expect(await repo.imageHashesOf(result.sessionId), ['single-h']);
  });

  test('去重只在页序完全一致时命中', () async {
    final provider = FakeAiProvider(fixturePath('multi_and_judge.json'));
    final workflow = mkWorkflow(provider);

    final first = await workflow.runMulti(
      pages: [page('d1', 1), page('d2', 2)],
      config: config,
    );
    expect(first.ok, isTrue);

    // 同页序 → 命中缓存，不再调用 AI，复用同一会话。
    final again = await workflow.runMulti(
      pages: [page('d1', 1), page('d2', 2)],
      config: config,
    );
    expect(again.cached, isTrue);
    expect(again.sessionId, first.sessionId);
    expect(provider.callCount, 1);

    // 首页相同但页数不同 → 必须重新分析（不能用错的页序复用）。
    final different = await workflow.runMulti(
      pages: [page('d1', 1), page('d2', 2), page('d3', 3)],
      config: config,
    );
    expect(different.cached, isFalse);
    expect(different.sessionId, isNot(first.sessionId));
    expect(provider.callCount, 2);
  });

  test('M47：raw_response 落库并可读回（ai-contract 第 5 步「保留原始响应」）', () async {
    final provider = FakeAiProvider(fixturePath('multi_and_judge.json'));
    final workflow = mkWorkflow(provider);
    final result = await workflow.run(
      jpeg: Uint8List.fromList([7, 7, 7]),
      imageHash: 'raw-h',
      width: 10,
      height: 10,
      config: config,
    );
    final session = (await repo.getSession(result.sessionId))!;
    expect(session.rawResponse, isNotNull, reason: 'AI 原始响应要留着供人工查看');
    expect(session.rawResponse, contains('"questions"'),
        reason: '存的应该是模型原样返回的 JSON');
    expect(Session.fromJson(session.toJson()).rawResponse, session.rawResponse,
        reason: '导出/备份的 JSON 往返也不能丢');
  });

  test('没有选中合集时仍能落库（拦截在 UI 层），合集为 null 表示未分类', () async {    final provider = FakeAiProvider(fixturePath('multi_and_judge.json'));
    final workflow = mkWorkflow(provider);
    final result = await workflow.run(
      jpeg: Uint8List.fromList([4, 4, 4]),
      imageHash: 'no-collection',
      width: 10,
      height: 10,
      config: config,
    );
    final session = (await repo.getSession(result.sessionId))!;
    expect(session.collectionId, isNull);
  });

  test('多页重新分析：从本机图片文件读回全部页', () async {
    final provider = FakeAiProvider(fixturePath('multi_and_judge.json'));
    final workflow = mkWorkflow(provider);

    final saved = <String, Uint8List>{};
    workflow.saveImageFile = (h, bytes) async => saved[h] = bytes;
    workflow.readImageFile = (h) async => saved[h];

    final first = await workflow.runMulti(
      pages: [page('r1', 1), page('r2', 2)],
      config: config,
    );
    expect(first.ok, isTrue);
    final callsBefore = provider.callCount;

    final retried = await workflow.retrySession(
      sessionId: first.sessionId,
      jpeg: saved['r1']!,
      config: config,
    );
    expect(retried.ok, isTrue);
    expect(provider.callCount, greaterThan(callsBefore), reason: '重新分析必须真的再问一次');
    expect(provider.lastImageCount, 2, reason: '两页都要带上');

    // 缺页时必须明确失败，而不是用残缺页序出结果。
    saved.remove('r2');
    expect(
      () => workflow.retrySession(
        sessionId: first.sessionId,
        jpeg: saved['r1']!,
        config: config,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
