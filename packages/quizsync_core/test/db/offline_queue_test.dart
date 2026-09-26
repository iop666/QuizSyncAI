import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import 'support.dart';

void main() {
  late QuizSyncDb db;
  late OfflineQueue queue;

  setUp(() async {
    db = createTestDb();
    queue = OfflineQueue(db);
  });

  tearDown(() async => db.close());

  test('入队到上限 20；第 21 条被拒绝（data-model.md 2.8）', () async {
    for (var i = 0; i < 20; i++) {
      await queue.enqueue(imageHash: 'h$i', sourceDevice: 'dev-b');
    }
    expect(await queue.queuedCount(), 20);
    expect(
      () => queue.enqueue(imageHash: 'h20', sourceDevice: 'dev-b'),
      throwsA(isA<QueueFullException>()),
    );
    expect(await queue.queuedCount(), 20);
  });

  test('上线后按 created_at 顺序补跑；成功置 done', () async {
    final t1 = await queue.enqueue(
        imageHash: 'h1', sourceDevice: 'dev-b', now: 1000);
    final t2 = await queue.enqueue(
        imageHash: 'h2', sourceDevice: 'dev-b', now: 2000);
    final t3 = await queue.enqueue(
        imageHash: 'h3', sourceDevice: 'dev-b', now: 3000);

    final seen = <String>[];
    final processed = await queue.drain((task) async {
      seen.add(task.taskId);
      return true;
    });

    expect(processed, 3);
    expect(seen, [t1.taskId, t2.taskId, t3.taskId], reason: '按入队顺序处理');
    expect(await queue.queuedCount(), 0);
    for (final t in [t1, t2, t3]) {
      final row = await (db.select(db.tasks)
            ..where((x) => x.taskId.equals(t.taskId)))
          .getSingle();
      expect(row.status, 'done');
      expect(row.finishedAt, isNotNull);
    }
  });

  test('提交失败：attempts+1，保持 queued，本次停止（等下次上线）', () async {
    final t1 = await queue.enqueue(
        imageHash: 'h1', sourceDevice: 'dev-b', now: 1000);
    await queue.enqueue(imageHash: 'h2', sourceDevice: 'dev-b', now: 2000);
    await queue.enqueue(imageHash: 'h3', sourceDevice: 'dev-b', now: 3000);

    final seen = <String>[];
    final processed = await queue.drain((task) async {
      seen.add(task.taskId);
      return task.taskId == t1.taskId; // 第一个成功，其余失败
    });

    expect(processed, 1);
    expect(seen.length, 2, reason: '失败后停止，不再处理第 3 条');
    expect(await queue.queuedCount(), 2);

    final row = await (db.select(db.tasks)..where((x) => x.taskId.equals(seen[1])))
        .getSingle();
    expect(row.status, 'queued');
    expect(row.attempts, 1);
  });

  test('QueueRetryLater：整体不可用时停止且不烧 attempts（用户需求 12）', () async {
    final t1 = await queue.enqueue(
        imageHash: 'h1',
        sourceDevice: 'dev-b',
        now: 1000,
        imageHashes: ['h1', 'h1b'],
        collectionId: 'c-1');
    await queue.enqueue(imageHash: 'h2', sourceDevice: 'dev-b', now: 2000);

    final seen = <String>[];
    final processed = await queue.drain((task) async {
      seen.add(task.taskId);
      // 主机还没选合集：不是这条任务的问题，别把 attempts 烧掉。
      throw QueueRetryLater('主机未选择任务合集');
    });

    expect(processed, 0);
    expect(seen.length, 1, reason: '第一条就整体不可用，本轮立即停止');
    expect(await queue.queuedCount(), 2);
    final row = await (db.select(db.tasks)..where((x) => x.taskId.equals(t1.taskId)))
        .getSingle();
    expect(row.status, 'queued');
    expect(row.attempts, 0, reason: '临时阻塞不得累加 attempts');

    // 离线入队时记下的多页页序与合集归属必须原样取回。
    final payload = OfflineQueue.parsePayload(row);
    expect(payload.imageHashes, ['h1', 'h1b']);
    expect(payload.collectionId, 'c-1');

    // 主机选好合集后同一批任务照常补跑。
    final processed2 = await queue.drain((task) async => true);
    expect(processed2, 2);
    expect(await queue.queuedCount(), 0);
  });

  test('自定义 taskId 幂等语义由调用方保证（同 id 重复入队按主键冲突处理）', () async {
    await queue.enqueue(
        imageHash: 'h1', sourceDevice: 'dev-b', taskId: 'fixed-id');
    expect(
      () => queue.enqueue(
          imageHash: 'h2', sourceDevice: 'dev-b', taskId: 'fixed-id'),
      throwsA(anything),
    );
  });
}
