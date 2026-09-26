import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import '../db/support.dart';

void main() {
  late QuizSyncDb db;
  late CoreRepository repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = createTestDb();
    repo = createTestRepo(db, 'dev-a');
    await repo.init();
  });

  tearDown(() async => db.close());

  Future<void> seedSession(String id, {int? deletedAt}) async {
    await repo.upsertSession(Session(
      sessionId: id,
      imageHash: 'h$id',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      createdAt: 1000,
      updatedAt: 1000,
      updatedBy: 'dev-a',
      deletedAt: deletedAt,
    ));
  }

  test('超过 30 天且对端已确认 → 物理清理；FTS 触发器同步清理', () async {
    final now = 100 * 24 * 3600 * 1000; // 100 天后
    await seedSession('old', deletedAt: 1000);
    await seedSession('fresh', deletedAt: now - 1000); // 刚删
    await db.into(db.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b',
          ackedLamport: const Value(99999),
        ));

    final removed = await tombstoneGc(repo, now: () => now);
    expect(removed, greaterThanOrEqualTo(1));

    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM sessions')
        .get();
    expect(rows.first.read<int>('c'), 1, reason: 'old 被物理清理，fresh 保留');
    expect(await repo.getSession('old', includeDeleted: true), isNull);
    expect(await repo.getSession('fresh', includeDeleted: true), isNotNull);
  });

  test('对端未确认删除 op → 保留', () async {
    final now = 100 * 24 * 3600 * 1000;
    await seedSession('old', deletedAt: 1000);
    // 对端 acked 落后：删除 op 的 lamport 高于 acked。
    await db.into(db.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b',
          ackedLamport: const Value(0),
        ));
    final removed = await tombstoneGc(repo, now: () => now);
    expect(removed, 0);
    expect(await repo.getSession('old', includeDeleted: true), isNotNull,
        reason: '删除 op 未被所有对端确认时不得物理清理');
  });

  test('30 天内删除 → 保留', () async {
    final now = 100 * 24 * 3600 * 1000;
    await seedSession('recent', deletedAt: now - 10 * 24 * 3600 * 1000); // 10 天前
    await db.into(db.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b', ackedLamport: const Value(99999)));
    final removed = await tombstoneGc(repo, now: () => now);
    expect(removed, 0);
    expect(await repo.getSession('recent', includeDeleted: true), isNotNull);
  });

  test('缺文件图片清单 + 补传写回不产生 op（data-model 2.4）', () async {
    await repo.upsertImage(const ImageMeta(
        hash: 'no-file',
        size: 10,
        mime: 'image/jpeg',
        createdAt: 1000,
        uploadedBy: 'dev-a'));
    await repo.upsertImage(const ImageMeta(
        hash: 'has-file',
        size: 10,
        mime: 'image/jpeg',
        localPath: 'C:/x.jpg',
        createdAt: 1000,
        uploadedBy: 'dev-a'));

    final missing = await imagesMissingFile(repo);
    expect(missing.map((m) => m.hash), ['no-file']);

    final before = await db.syncOpsCount();
    await repo.setImageLocalPath('no-file', 'C:/new.jpg');
    expect(await db.syncOpsCount(), before, reason: 'local_path 写回不产生 op');
  });

  test('本地文件清理：超上限删最旧并置 NULL', () async {
    for (var i = 0; i < 5; i++) {
      await repo.upsertImage(ImageMeta(
          hash: 'img$i',
          size: 1,
          mime: 'image/jpeg',
          localPath: 'C:/$i.jpg',
          createdAt: 1000 + i,
          uploadedBy: 'dev-a'));
    }
    final removed = await pruneImageFiles(repo, (hash) => 'C:/$hash.jpg', maxFiles: 2);
    expect(removed, 3);
    final remaining = await db.customSelect(
        "SELECT COUNT(*) AS c FROM images WHERE local_path IS NOT NULL").get();
    expect(remaining.first.read<int>('c'), 2);
    // 元数据保留。
    final all = await db.customSelect('SELECT COUNT(*) AS c FROM images').get();
    expect(all.first.read<int>('c'), 5);
  });

  test('M47：离线队列引用的原图不被清理（队首任务的原图最旧，正好第一个被剪）',
      () async {
    for (var i = 0; i < 5; i++) {
      await repo.upsertImage(ImageMeta(
          hash: 'img$i',
          size: 1,
          mime: 'image/jpeg',
          localPath: 'C:/$i.jpg',
          createdAt: 1000 + i,
          uploadedBy: 'dev-a'));
    }
    // 最旧的那张（img0）正被一条排队中的任务引用。
    final removed = await pruneImageFiles(repo, (hash) => 'C:/$hash.jpg',
        maxFiles: 2, keep: const {'img0'});
    expect(removed, 2, reason: '要删够数，但不能动被引用的那张');
    final kept = await repo.getImage('img0');
    expect(kept!.localPath, 'C:/0.jpg', reason: '补跑必须还能从磁盘取到原图');
    final gone = await repo.getImage('img1');
    expect(gone!.localPath, isNull, reason: '没被引用的最旧一张照常剪掉');

    // 不传 keep 时行为不变（老用例的口径）。
    final removed2 = await pruneImageFiles(repo, (hash) => 'C:/$hash.jpg', maxFiles: 1);
    expect(removed2, 2);
    expect((await repo.getImage('img0'))!.localPath, isNull);
  });
}
