import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import 'support.dart';

/// 模拟双端：dev-a / dev-b 各一个库，op 手工搬运（M4 之后由网络层搬运）。
void main() {
  late QuizSyncDb dbA;
  late QuizSyncDb dbB;
  late CoreRepository repoA;
  late CoreRepository repoB;

  setUp(() async {
    dbA = createTestDb();
    dbB = createTestDb();
    repoA = createTestRepo(dbA, 'dev-a');
    repoB = createTestRepo(dbB, 'dev-b');
    await repoA.init();
    await repoB.init();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  Future<List<SyncOp>> opsOf(QuizSyncDb db) async {
    final rows = await db.select(db.syncOps).get();
    return rows.map(opFromRow).toList();
  }

  Future<void> syncAtoB() async {
    for (final op in await opsOf(dbA)) {
      await repoB.applyRemoteOp(op);
    }
  }

  test('A 的 session op 应用到 B：两端数据一致', () async {
    final created = await repoA.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      questionCount: 3,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    await syncAtoB();

    final bSession = await repoB.getSession('s1');
    expect(bSession, isNotNull);
    expect(bSession!.status, TaskState.done);
    expect(bSession.questionCount, 3);
    expect(bSession.imageHash, 'h1');
    expect(bSession.updatedBy, 'dev-a');
    expect(bSession.lamport, created.lamport);

    // B 也把收到的 op 记进了自己的 sync_ops（回环验证第 7 步的基础）
    expect((await opsOf(dbB)).length, 1);
  });

  test('重复 op 按 op_id 忽略，无副作用（data-model.md 2.9 场景 6）', () async {
    await repoA.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.queued,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    final op = (await opsOf(dbA)).single;
    await repoB.applyRemoteOp(op);
    final again = await repoB.applyRemoteOp(op);

    expect(again.duplicate, isTrue);
    expect((await opsOf(dbB)).length, 1, reason: 'op 不重复入库');
    final sessions = await repoB.listSessions();
    expect(sessions.length, 1);
  });

  test('B 收到更新的字段写入 → 覆盖；更旧的 → 跳过', () async {
    await repoA.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.queued,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    final op1 = (await opsOf(dbA)).first;

    // 更新 status 的第二个 op
    final s = await repoA.getSession('s1');
    await repoA.upsertSession(s!.copyWith(status: TaskState.analyzing));
    final op2 = (await opsOf(dbA)).last;

    // 乱序到达：先 op2 后 op1
    await repoB.applyRemoteOp(op2);
    await repoB.applyRemoteOp(op1);
    expect((await repoB.getSession('s1'))!.status, TaskState.analyzing,
        reason: 'op1 (lamport 1) 比 op2 (lamport 2) 旧，不能把 status 改回去');
  });

  test('删除在两端最终一致（2.9 场景 4）', () async {
    await repoA.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
    ));
    await syncAtoB();
    expect(await repoB.getSession('s1'), isNotNull);

    await repoA.deleteSession('s1');
    await syncAtoB();

    expect(await repoA.listSessions(), isEmpty);
    expect(await repoB.listSessions(), isEmpty);
    expect((await repoB.getSession('s1', includeDeleted: true))!.deletedAt,
        isNotNull);
  });

  test('同一图片两端各上传一次 → 按 hash 合并（2.9 场景 5）', () async {
    await repoA.upsertImage(const ImageMeta(
      hash: 'shared-hash',
      size: 123,
      mime: 'image/jpeg',
      width: 1600,
      height: 900,
      createdAt: 1000,
      uploadedBy: 'dev-a',
    ));
    await syncAtoB();

    // B 自己也插入同一 hash
    await repoB.upsertImage(const ImageMeta(
      hash: 'shared-hash',
      size: 123,
      mime: 'image/jpeg',
      width: 1600,
      height: 900,
      createdAt: 1000,
      uploadedBy: 'dev-b',
    ));

    final countRows = await dbB
        .customSelect('SELECT COUNT(*) AS c FROM images')
        .get();
    expect(countRows.first.read<int>('c'), 1);
    expect(await repoB.getImage('shared-hash'), isNotNull);
  });

  test('远端 op 触碰 user_edited 字段 → 保护并记录待覆盖提示', () async {
    // B 端有用户手改答案的题目
    await repoB.upsertSession(Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-b',
      status: TaskState.done,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-b',
    ));
    await repoB.upsertQuestion(Question(
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      stem: '题干',
      type: QuestionType.single,
      options: const [Option(label: 'A', text: 'a'), Option(label: 'B', text: 'b')],
      choice: const ['A'],
      analysis: 'B 端解析',
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-b',
    ));
    await repoB.updateUserAnswer('q1', const AnswerValue(choice: ['A']));

    // A 端（AI 所在端）重新分析出 B
    final result = await repoB.applyRemoteOp(SyncOp(
      opId: 'op-remote-1',
      deviceId: 'dev-a',
      lamport: 100,
      entity: SyncEntity.question,
      entityId: 'q1',
      opType: SyncOpType.upsert,
      fields: {
        'choice_json': '["B"]',
        'analysis': 'A 端新解析',
      },
      createdAt: 5000,
    ));

    expect(result.protectedFields, contains('choice_json'));
    final q = await repoB.getQuestion('q1');
    expect(q!.choice, ['A'], reason: '用户手改不被静默覆盖');
    expect(q.analysis, 'A 端新解析', reason: '未保护的字段正常应用');

    // 待覆盖提示被记录，可读取（peek 不消费）
    final pending = await repoB.peekPendingOverwrite('q1');
    expect(pending, isNotNull);
    expect(pending!['fields'], containsPair('choice_json', '["B"]'));

    // 用户显式确认覆盖 → 应用并清标记
    await repoB.confirmPendingOverwrite('q1');
    final after = await repoB.getQuestion('q1');
    expect(after!.choice, ['B']);
    expect(after.answerEdited, isFalse);
  });

  test('Lamport 时钟被远端 op 推高（跨库）', () async {
    await repoB.applyRemoteOp(SyncOp(
      opId: 'op-remote-1',
      deviceId: 'dev-a',
      lamport: 50,
      entity: SyncEntity.image,
      entityId: 'h1',
      opType: SyncOpType.upsert,
      fields: {'size': 10, 'mime': 'image/jpeg', 'uploaded_by': 'dev-a'},
      createdAt: 1000,
    ));
    expect(repoB.clock.value, 51);
  });
}
