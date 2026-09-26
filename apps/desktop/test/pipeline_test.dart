import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_desktop/state/analysis_workflow.dart';

void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
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

  const config = AiConfig(model: 'test-model');

  test('全链路：JPEG → 会话/任务 → AI → 题目 → sync_ops（M3 任务 6）', () async {
    final fixture =
        File('../../packages/quizsync_core/test/fixtures/multi_and_judge.json')
            .absolute.path;
    final provider = FakeAiProvider(fixture);
    final workflow = mkWorkflow(provider);

    final result = await workflow.run(
      jpeg: Uint8List.fromList([1, 2, 3]),
      imageHash: 'hash-full-chain',
      width: 1600,
      height: 900,
      config: config,
    );

    expect(result.ok, isTrue);
    expect(result.cached, isFalse);
    expect(provider.callCount, 1);

    final session = await repo.getSession(result.sessionId);
    expect(session!.status, TaskState.done);
    expect(session.questionCount, 2);
    expect(session.aiModel, 'test-model');
    expect(session.promptVersion, computePromptVersion());

    final questions = await repo.questionsOfSession(result.sessionId);
    expect(questions.length, 2);
    expect(questions[0].type, QuestionType.multi);
    expect(computeHighlight(questions[0]).optionLabels, {'A', 'C', 'D'});
    expect(computeHighlight(questions[1]).optionLabels, {'对'});

    // 图片元数据入库
    final image = await repo.getImage('hash-full-chain');
    expect(image, isNotNull);
    expect(image!.width, 1600);

    // sync_ops：图片 1 + 会话 2（建 + done）+ 题目 2
    final ops = await db.select(db.syncOps).get();
    expect(ops.length, greaterThanOrEqualTo(5));
    expect(ops.map((o) => o.entity).toSet(),
        containsAll(['image', 'session', 'question']));

    // 任务完成
    final tasks = await db.select(db.tasks).get();
    expect(tasks.single.status, 'done');
    expect(tasks.single.sessionId, result.sessionId);
  });

  test('同图去重：同一 hash 第二次直接跳到上次结果（不调 AI）', () async {
    final fixture =
        File('../../packages/quizsync_core/test/fixtures/single_choice.json')
            .absolute.path;
    final provider = FakeAiProvider(fixture);
    final workflow = mkWorkflow(provider);
    const config2 = AiConfig(model: 'test-model');

    final first = await workflow.run(
      jpeg: Uint8List.fromList([9]),
      imageHash: 'dup-hash',
      width: 100,
      height: 100,
      config: config2,
    );
    expect(first.cached, isFalse);

    final second = await workflow.run(
      jpeg: Uint8List.fromList([9]),
      imageHash: 'dup-hash',
      width: 100,
      height: 100,
      config: config2,
    );
    expect(second.cached, isTrue);
    expect(second.sessionId, first.sessionId);
    expect(second.message, contains('之前搜过'));
    expect(provider.callCount, 1, reason: '第二次不调用 AI');
  });

  test('失败路径：AI 401 → 会话 failed + ai_auth + 保留重试入口', () async {
    final provider = _ScriptedProvider([
      const AiException(AiErrorKind.auth, 'Key 无效', statusCode: 401),
    ]);
    final workflow = AnalysisWorkflow(
      repo: repo,
      engine: AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db),
        deviceId: 'windows-local',
      ),
      deviceId: 'windows-local',
    );

    final result = await workflow.run(
      jpeg: Uint8List.fromList([1]),
      imageHash: 'auth-fail-hash',
      width: 10,
      height: 10,
      config: config,
    );

    expect(result.ok, isFalse);
    expect(result.errorCode, 'ai_auth');
    final session = await repo.getSession(result.sessionId);
    expect(session!.status, TaskState.failed);
    expect(session.errorCode, 'ai_auth');
    // 图片保留（重试用）
    expect(await repo.getImage('auth-fail-hash'), isNotNull);
  });

  test('重试：失败会话 retrySession 复用同一会话', () async {
    final provider = _ScriptedProvider([
      const AiException(AiErrorKind.timeout, '超时'),
      const AiException(AiErrorKind.timeout, '超时'),
      const AiException(AiErrorKind.timeout, '超时'),
      // 重试时成功
      _fixtureResponse('single_choice.json'),
    ]);
    final workflow = AnalysisWorkflow(
      repo: repo,
      engine: AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db),
        deviceId: 'windows-local',
        retry: const RetryPolicy(sleeper: _noSleep),
      ),
      deviceId: 'windows-local',
    );

    final failed = await workflow.run(
      jpeg: Uint8List.fromList([5]),
      imageHash: 'retry-hash',
      width: 10,
      height: 10,
      config: config,
    );
    expect(failed.errorCode, 'ai_timeout');

    final retried = await workflow.retrySession(
      sessionId: failed.sessionId,
      jpeg: Uint8List.fromList([5]),
      config: config,
    );
    expect(retried.sessionId, failed.sessionId, reason: '重试复用同一会话');
    expect(retried.ok, isTrue);
    expect((await repo.questionsOfSession(failed.sessionId)).length, 1);
  });
}

AiRawResponse _fixtureResponse(String name) => AiRawResponse(
    text: File('../../packages/quizsync_core/test/fixtures/$name')
        .readAsStringSync(),
    latencyMs: 5);

Future<void> _noSleep(Duration d) async {}

class _ScriptedProvider extends QuizAiProvider {
  final List<Object> script;
  int callCount = 0;

  _ScriptedProvider(this.script);

  @override
  String get id => 'scripted';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    final item = script[callCount.clamp(0, script.length - 1)];
    callCount++;
    if (item is AiException) throw item;
    return item as AiRawResponse;
  }
}
