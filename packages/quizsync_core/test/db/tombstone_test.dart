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

  Future<void> seedSessionWithQuestion() async {
    final s = await repo.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    await repo.upsertQuestion(Question(
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      stem: '二次方程的求根公式是什么',
      analysis: r'$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$',
      type: QuestionType.blank,
      answerText: 'x = (-b ± √(b²-4ac)) / 2a',
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      updatedBy: 'dev-a',
    ));
  }

  test('删除前 FTS 能搜到（题干与解析）', () async {
    await seedSessionWithQuestion();
    final byStem = await repo.searchQuestions('求根');
    expect(byStem.length, 1);
    final byAnalysis = await repo.searchQuestions('sqrt');
    expect(byAnalysis.length, 1);
  });

  test('软删除后：列表不可见、按 id 不可见、FTS 也搜不到（data-model.md 2.7）', () async {
    await seedSessionWithQuestion();
    await repo.deleteSession('s1');

    expect(await repo.listSessions(), isEmpty);
    expect(await repo.getSession('s1'), isNull);
    expect(await repo.getSession('s1', includeDeleted: true), isNotNull,
        reason: 'tombstone 行本身保留');
    expect(await repo.questionsOfSession('s1'), isEmpty);
    expect(await repo.searchQuestions('求根'), isEmpty,
        reason: 'FTS join 后排除了软删除');
    expect(await repo.searchQuestions('sqrt'), isEmpty);
  });

  test('列表按时间倒序', () async {
    for (var i = 1; i <= 3; i++) {
      await repo.upsertSession(Session(
        sessionId: 's$i',
        imageHash: 'h$i',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1000 * i,
        updatedAt: 1000 * i,
        updatedBy: 'dev-a',
      ));
    }
    final list = await repo.listSessions();
    expect(list.map((s) => s.sessionId).toList(), ['s3', 's2', 's1']);
  });
}
