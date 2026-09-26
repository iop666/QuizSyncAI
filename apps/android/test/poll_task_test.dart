import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/state/app_state.dart';

import 'support.dart';

/// 轮询兜底路径（`pollTaskUntilDone`）的结果落库。
///
/// 这条路径与 WS 的 `task_result`（`live_updates.dart` 的 `_taskResult`）
/// 必须**同一口径**：题目一律走 `applyAnalysisResult`（`data-model.md` 2.3），
/// 否则主机重分析推回的结果会把用户手改直接盖掉。
class _FakeTaskApi extends ApiClient {
  _FakeTaskApi(this.view) : super(baseUrl: 'http://127.0.0.1:1', token: 't');

  TaskStatusView view;
  int getTaskCalls = 0;

  @override
  Future<TaskStatusView> getTask(String taskId) async {
    getTaskCalls++;
    return view;
  }
}

Session _session({
  String sessionId = 's1',
  int updatedAt = 2000,
  int questionCount = 1,
}) =>
    Session(
      sessionId: sessionId,
      collectionId: 'c1',
      imageHash: 'h1',
      sourceDevice: 'android-local',
      status: TaskState.done,
      questionCount: questionCount,
      createdAt: 1000,
      updatedAt: updatedAt,
      updatedBy: 'server-1',
    );

Question _question({
  String questionId = 'q1',
  String sessionId = 's1',
  String answerText = 'AI 新答案',
  String analysis = 'AI 新解析',
  int updatedAt = 2000,
}) =>
    Question(
      questionId: questionId,
      sessionId: sessionId,
      ordinal: 0,
      questionNo: '12',
      stem: '题干',
      type: QuestionType.blank,
      answerText: answerText,
      analysis: analysis,
      createdAt: 1000,
      updatedAt: updatedAt,
      updatedBy: 'server-1',
    );

void main() {
  late QuizSyncDb db;
  late AndroidAppState app;

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
  });

  tearDown(() async => db.close());

  test('轮询结果不覆盖用户手改过的答案与解析（唯一 P0 数据缺陷）', () async {
    // 同一会话先前的结果已经落过库（题目 id 是主机给的，两端一致），
    // 用户在手机上改了答案与解析 → answer_edited / analysis_edited = 1。
    await app.repo.upsertSession(_session(updatedAt: 1000));
    await app.repo.upsertQuestion(_question(answerText: 'AI 答案', analysis: 'AI 解析'));
    await app.repo.updateUserAnswer('q1', const AnswerValue(text: '我改的答案'));
    await app.repo.updateUserAnalysis('q1', '我改的解析');

    // 主机重新识别，兜底轮询拉回同一条会话的新结果。
    final api = _FakeTaskApi(TaskStatusView(
      taskId: 't1',
      status: 'done',
      sessionId: 's1',
      session: _session(),
      questions: [_question()],
      imageHashes: const ['h1'],
    ));

    final outcome = await pollTaskUntilDone(api, app.repo, 't1');
    expect(api.getTaskCalls, 1);
    expect(outcome.ok, isTrue);
    expect(outcome.sessionId, 's1');

    final after = (await app.repo.getQuestion('q1'))!;
    expect(after.answerText, '我改的答案',
        reason: '用户手改的答案不得被轮询结果覆盖（data-model.md 2.3）');
    expect(after.analysis, '我改的解析', reason: '用户手改的解析同理');
    expect(after.answerEdited, isTrue, reason: '手改标记必须留着，否则下一次同步会把 AI 值当成本地值推回主机');
    expect(after.analysisEdited, isTrue);
    expect(await app.repo.questionsOfSession('s1'), hasLength(1),
        reason: '按 ordinal 与既有题目对应，不得插入第二行');
  });

  test('首次轮询：会话（带 taskId）+ 题目 + 页序一起落库', () async {
    final api = _FakeTaskApi(TaskStatusView(
      taskId: 't9',
      status: 'done',
      sessionId: 's9',
      session: _session(sessionId: 's9'),
      questions: [_question(sessionId: 's9')],
      imageHashes: const ['h1', 'h2'],
    ));

    final outcome = await pollTaskUntilDone(api, app.repo, 't9');
    expect(outcome.ok, isTrue);
    expect(outcome.sessionId, 's9');

    final session = (await app.repo.getSession('s9'))!;
    expect(session.taskId, 't9', reason: '幂等 id 要落在本地会话上');
    expect(session.status, TaskState.done);
    expect(session.questionCount, 1);
    expect((await app.repo.getQuestion('q1'))!.stem, '题干');
    expect(await app.repo.imageHashesOf('s9'), ['h1', 'h2']);
  });

  test('失败任务：带回错误码与原因，不落库', () async {
    final api = _FakeTaskApi(const TaskStatusView(
      taskId: 't1',
      status: 'failed',
      errorCode: 'ai_error',
      errorMessage: 'AI 超时',
    ));

    final outcome = await pollTaskUntilDone(api, app.repo, 't1');
    expect(outcome.ok, isFalse);
    expect(outcome.errorCode, 'ai_error');
    expect(outcome.errorMessage, 'AI 超时');
    expect(await app.repo.getSession('s1'), isNull);
  });
}
