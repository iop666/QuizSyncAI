import 'dart:convert';

import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import 'support.dart';

void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    db = createTestDb();
    repo = createTestRepo(db, 'dev-a');
    await repo.init();
  });

  tearDown(() async => db.close());

  Question aiQuestion({
    String choice = '["B"]',
    String answerText = 'null',
    String analysis = 'AI 解析',
  }) =>
      Question(
        questionId: 'q-ai',
        sessionId: 's1',
        ordinal: 0,
        stem: '题干',
        type: QuestionType.single,
        options: const [Option(label: 'A', text: 'a'), Option(label: 'B', text: 'b')],
        createdAt: 1000,
        updatedAt: 1000,
        updatedBy: 'dev-a',
      ).copyWith(
        choice: (choice == 'null')
            ? const []
            : (jsonDecode(choice) as List).map((e) => e.toString()).toList(),
        answerText: answerText == 'null' ? null : answerText,
        analysis: analysis,
      );

  Future<void> seedExistingQuestion(Question q) async {
    await repo.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    await repo.upsertQuestion(q);
  }

  test('用户手改答案 → AI 重新分析不覆盖答案，但更新解析（data-model.md 2.3）', () async {
    await seedExistingQuestion(aiQuestion(choice: '["B"]'));
    await repo.updateUserAnswer('q-ai', const AnswerValue(choice: ['A']));

    await repo.applyAnalysisResult(
      sessionId: 's1',
      input: AnalysisResultInput(
        aiProvider: 'openai-compatible',
        questions: [aiQuestion(choice: '["B"]', analysis: '新的 AI 解析')],
      ),
    );

    final q = await repo.getQuestion('q-ai');
    expect(q!.choice, ['A'], reason: '用户手改的答案必须保留');
    expect(q.answerEdited, isTrue);
    expect(q.analysis, '新的 AI 解析', reason: '未手改解析 → AI 更新生效');
  });

  test('用户手改解析 → AI 重新分析不覆盖解析', () async {
    await seedExistingQuestion(aiQuestion(analysis: '旧解析'));
    await repo.updateUserAnalysis('q-ai', '用户补充的解析');

    await repo.applyAnalysisResult(
      sessionId: 's1',
      input: AnalysisResultInput(
        questions: [aiQuestion(analysis: 'AI 又给了新解析')],
      ),
    );

    final q = await repo.getQuestion('q-ai');
    expect(q!.analysis, '用户补充的解析');
    expect(q.analysisEdited, isTrue);
  });

  test('重分析题目数变少 → 多出的旧题软删除', () async {
    await seedExistingQuestion(aiQuestion());
    await repo.upsertQuestion(Question(
      questionId: 'q2',
      sessionId: 's1',
      ordinal: 1,
      stem: '第二题',
      type: QuestionType.blank,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));

    await repo.applyAnalysisResult(
      sessionId: 's1',
      input: const AnalysisResultInput(questions: []),
    );

    expect(await repo.questionsOfSession('s1'), isEmpty);
  });

  test('questions 为空 → session failed + no_question_found', () async {
    await seedExistingQuestion(aiQuestion());
    await repo.applyAnalysisResult(
      sessionId: 's1',
      input: const AnalysisResultInput(questions: []),
    );
    final s = await repo.getSession('s1');
    expect(s!.status, TaskState.failed);
    expect(s.errorCode, 'no_question_found');
  });
}
