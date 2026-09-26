import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import 'support.dart';

Session newSession(String id, {String? imageHash, int createdAt = 1000}) =>
    Session(
      sessionId: id,
      taskId: 'task-$id',
      imageHash: imageHash ?? 'hash-$id',
      sourceDevice: 'dev-a',
      status: TaskState.queued,
      createdAt: createdAt,
      updatedAt: createdAt,
      updatedBy: 'dev-a',
    );

Future<List<SyncOpRow>> opsOf(QuizSyncDb db, {String? entityId}) async {
  var q = db.select(db.syncOps);
  if (entityId != null) {
    q = q..where((t) => t.entityId.equals(entityId));
  }
  final rows = await q.get();
  return rows;
}

void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    db = createTestDb();
    repo = createTestRepo(db, 'dev-a');
    await repo.init();
  });

  tearDown(() async => db.close());

  test('新建 session：恰好 1 条 op，字段为全量', () async {
    await repo.upsertSession(newSession('s1'));
    final ops = await opsOf(db, entityId: 's1');
    expect(ops.length, 1);
    final op = opFromRow(ops.single);
    expect(op.entity, SyncEntity.session);
    expect(op.opType, SyncOpType.upsert);
    expect(op.deviceId, 'dev-a');
    expect(op.fields.containsKey('status'), isTrue);
    expect(op.fields.containsKey('image_hash'), isTrue);
    expect(op.fields.containsKey('created_at'), isTrue);
  });

  test('更新单个字段：第 2 条 op 只含变更字段', () async {
    final s = await repo.upsertSession(newSession('s1'));
    await repo.upsertSession(
        s.copyWith(status: TaskState.analyzing, updatedAt: 2000));
    final ops = await opsOf(db, entityId: 's1');
    expect(ops.length, 2);

    final second = opFromRow(ops.last);
    expect(second.opType, SyncOpType.upsert);
    expect(second.fields.containsKey('status'), isTrue);
    // 未变更的字段不进 op
    expect(second.fields.containsKey('image_hash'), isFalse);
    expect(second.fields.containsKey('created_at'), isFalse);
    expect(second.fields.containsKey('ai_provider'), isFalse);
  });

  test('最小变更：未变的业务字段不进 op', () async {
    final s = await repo.upsertSession(newSession('s1'));
    await repo.upsertSession(
        s.copyWith(status: TaskState.analyzing, updatedAt: 2000));
    final ops = await opsOf(db, entityId: 's1');
    expect(ops.length, 2);
    final second = opFromRow(ops.last);
    // 只允许 status 与时间戳元数据出现在变更集里
    expect(second.fields.keys.toSet()
        .difference({'status', 'updated_at', 'updated_by'}),
        isEmpty,
        reason: '未变更的字段不得进入 fields_json');
  });

  test('lamport 严格递增', () async {
    await repo.upsertSession(newSession('s1'));
    final s = await repo.getSession('s1');
    await repo.upsertSession(s!.copyWith(status: TaskState.analyzing));
    final ops = await opsOf(db);
    final lamports = ops.map((o) => o.lamport).toList();
    expect(lamports, [1, 2]);
  });

  test('删除 session：session 1 条 delete op + 每题 1 条 delete op', () async {
    final s = await repo.upsertSession(newSession('s1'));
    await repo.upsertQuestion(Question(
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      stem: '题干',
      type: QuestionType.single,
      options: const [Option(label: 'A', text: 'a'), Option(label: 'B', text: 'b')],
      choice: const ['B'],
      createdAt: s.createdAt,
      updatedAt: s.createdAt,
      updatedBy: 'dev-a',
    ));
    await repo.upsertQuestion(Question(
      questionId: 'q2',
      sessionId: 's1',
      ordinal: 1,
      stem: '第二题',
      type: QuestionType.blank,
      answerText: '42',
      createdAt: s.createdAt,
      updatedAt: s.createdAt,
      updatedBy: 'dev-a',
    ));

    await repo.deleteSession('s1');

    final sessionOps = await opsOf(db, entityId: 's1');
    expect(sessionOps.where((o) => o.opType == 'delete').length, 1);
    final q1Ops = await opsOf(db, entityId: 'q1');
    final q2Ops = await opsOf(db, entityId: 'q2');
    expect(q1Ops.where((o) => o.opType == 'delete').length, 1);
    expect(q2Ops.where((o) => o.opType == 'delete').length, 1);
    // delete op 的 fields 带 deleted_at
    final del = opFromRow(sessionOps.last);
    expect(del.opType, SyncOpType.delete);
    expect(del.fields.containsKey('deleted_at'), isTrue);
  });

  test('image upsert：local_path 不进 op（data-model.md 2.4）', () async {
    await repo.upsertImage(const ImageMeta(
      hash: 'h1',
      size: 100,
      mime: 'image/jpeg',
      localPath: 'C:/data/img.jpg',
      createdAt: 1000,
      uploadedBy: 'dev-a',
    ));
    final ops = await opsOf(db, entityId: 'h1');
    expect(ops.length, 1);
    expect(opFromRow(ops.single).fields.containsKey('local_path'), isFalse);

    // setImageLocalPath 不产生新 op
    await repo.setImageLocalPath('h1', 'C:/other.jpg');
    expect((await opsOf(db)).length, 1);
  });
}
