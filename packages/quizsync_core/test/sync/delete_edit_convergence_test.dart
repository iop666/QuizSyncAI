import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import '../db/support.dart';

/// M47：删除 vs 修改的收敛（`data-model.md` 2.9 场景 7）。
///
/// 契约原话：「Android 离线删除了某会话，Windows 同时修改了它 —— 删除胜出
/// （墓碑时间戳更大）或修改胜出，取决于时间戳；**两端最终一致，不得出现一端删
/// 一端在的永久分叉**」。
///
/// 老实现的漏洞：删除是「往 `deleted_at` 写时间戳」，参与字段级 LWW，可它输掉的
/// 时候**没有人回头**：A 离线删（lamport 低）、B 同时改（lamport 高）→ B 按 LWW
/// 拒掉删除、A 的墓碑永远留着，两端永久分叉。
///
/// 现在的规则：**lamport 大者赢，输的一方跟着改**。
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

  /// 把 [from] 库里的全部 op 喂给 [to]（按 op_id 幂等，重复搬没关系）。
  Future<void> deliver(QuizSyncDb from, CoreRepository to) async {
    for (final row in await from.select(from.syncOps).get()) {
      await to.applyRemoteOp(opFromRow(row));
    }
  }

  Future<Session> newSession(CoreRepository repo, String device) => repo.upsertSession(
        Session(
          sessionId: 's1',
          imageHash: 'h1',
          sourceDevice: device,
          status: TaskState.done,
          questionCount: 0,
          createdAt: 1000,
          updatedAt: 1000,
          updatedBy: device,
        ),
      );

  test('删除输给更新的修改：删除方跟着复活（对端只发变更字段时）', () async {
    // 现实来源：手机端那行是**本地落库**的（主机把结果推过来、手机自己写库，
    // 见 android `live_updates.dart`），所以 lamport 很小；主机端同一行是自己建的，
    // lamport 早就涨上去了。手机随后删掉它 → 删除 op 的 lamport 比主机那行还低。
    await repoB.applyRemoteOp(SyncOp(
      opId: 'op-warmup',
      deviceId: 'dev-c',
      lamport: 100,
      entity: SyncEntity.image,
      entityId: 'h-x',
      opType: SyncOpType.upsert,
      fields: {'size': 1, 'mime': 'image/jpeg', 'uploaded_by': 'dev-c'},
      createdAt: 1,
    ));
    await newSession(repoB, 'dev-b'); // B 的行 lamport = 101
    await newSession(repoA, 'dev-a'); // A 的行 lamport = 1（本地落库）

    await repoA.deleteSession('s1'); // A 的 delete op lamport = 2
    expect(await repoA.getSession('s1'), isNull, reason: '本端先删掉了');

    // 主机随后只改了一个字段（`diffFields` 决定 op 里**没有** `deleted_at`），
    // 手机拉到这一条 —— 老实现里墓碑纹丝不动，两端就此永久分叉。
    final edited = await repoB.upsertSession(
        (await repoB.getSession('s1'))!.copyWith(questionCount: 7));
    final op = (await dbB.select(dbB.syncOps).get())
        .map(opFromRow)
        .firstWhere((o) => o.entityId == 's1' && o.lamport == edited.lamport);
    expect(op.fields.containsKey('deleted_at'), isFalse,
        reason: '这条 op 只含变更字段（这条用例的前提）');

    await repoA.applyRemoteOp(op);

    expect(await repoB.getSession('s1'), isNotNull,
        reason: '更新的那一端赢过更低的 lamport 删除');
    final a = await repoA.getSession('s1');
    expect(a, isNotNull,
        reason: '删除输掉时，删除方必须跟着复活（data-model.md 2.9：不得永久分叉）');
    expect(a!.questionCount, 7);
    expect(a.deletedAt, isNull);
  });

  test('删除的 lamport 更高：删除赢，两端都删', () async {
    await newSession(repoA, 'dev-a');
    await deliver(dbA, repoB);

    await repoB.upsertSession(
        (await repoB.getSession('s1'))!.copyWith(questionCount: 3));
    await deliver(dbB, repoA); // A 的时钟被推高

    await repoA.deleteSession('s1'); // lamport 高于 B 的行
    await deliver(dbA, repoB);

    expect(await repoA.getSession('s1'), isNull);
    expect(await repoB.getSession('s1'), isNull, reason: '更高的 lamport 删除要赢');
    expect(await repoB.getSession('s1', includeDeleted: true), isNotNull,
        reason: '墓碑行保留（物理清理另有 30 天规则）');
  });

  test('两端同时删：墓碑时间戳也收敛到同一个值', () async {
    await newSession(repoA, 'dev-a');
    await deliver(dbA, repoB);

    await repoA.deleteSession('s1');
    // 让 B 的 lamport 高一点，形成「同一字段、不同 lamport」的竞争。
    await repoB.upsertSession(
        (await repoB.getSession('s1'))!.copyWith(questionCount: 1));
    await repoB.deleteSession('s1');

    await deliver(dbA, repoB);
    await deliver(dbB, repoA);

    final a = (await repoA.getSession('s1', includeDeleted: true))!;
    final b = (await repoB.getSession('s1', includeDeleted: true))!;
    expect(a.deletedAt, isNotNull);
    expect(b.deletedAt, isNotNull);
    expect(a.deletedAt, b.deletedAt, reason: '输的一方要跟着改成赢家的时间戳');
  });
}
