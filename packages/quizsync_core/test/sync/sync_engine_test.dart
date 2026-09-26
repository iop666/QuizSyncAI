import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

import '../db/support.dart';

void main() {
  late QuizSyncDb dbA;
  late CoreRepository repoA;
  late QuizSyncDb dbB;
  late CoreRepository repoB;
  late SyncEngine engineA;
  late SyncEngine engineB;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dbA = createTestDb();
    repoA = createTestRepo(dbA, 'dev-a');
    await repoA.init();
    dbB = createTestDb();
    repoB = createTestRepo(dbB, 'dev-b');
    await repoB.init();
    engineA = SyncEngine(repo: repoA, localDeviceId: 'dev-a');
    engineB = SyncEngine(repo: repoB, localDeviceId: 'dev-b');
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  Future<void> seedA(int n) async {
    for (var i = 0; i < n; i++) {
      await repoA.upsertSession(Session(
        sessionId: 's$i',
        imageHash: 'h$i',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: i,
        updatedAt: i,
        updatedBy: 'dev-a',
      ));
    }
  }

  test('推拉：A 推 → B 拉 → 应用；水位线推进；重复 reconcile 无新数据', () async {
    await seedA(3);

    // A 推给 B（经内存直传）。
    final pushed = await engineA.pushToPeer('dev-b', (ops) async {
      await engineB.pullFromPeer('dev-a', (since) async => ops);
    });
    expect(pushed, greaterThanOrEqualTo(3));
    expect((await repoB.listSessions()).length, 3);

    // A 的 sent 水位已推进 → 再推为空。
    final again = await engineA.opsToPush('dev-b');
    expect(again, isEmpty);

    // B 侧 acked 水位推进 → 再拉为空（拉取从 since=acked 开始）。
    final pulledAgain = await engineB.pullFromPeer(
        'dev-a', (since) async => (await engineA.opsToPush('dev-b')));
    // opsToPush 基于 sent 水位（已推进），因此为空。
    expect(pulledAgain, 0);
  });

  test('reconcile（先拉后推）：双向交换后两端一致', () async {
    await seedA(2);
    await repoB.upsertSession(Session(
      sessionId: 'bs1',
      imageHash: 'bh1',
      sourceDevice: 'dev-b',
      status: TaskState.done,
      createdAt: 10,
      updatedAt: 10,
      updatedBy: 'dev-b',
    ));

    // A reconcile B：拉 B 的 op（A 的库有 B 的数据）+ 推 A 的 op 给 B。
    await engineA.reconcile(
      'dev-b',
      fetcher: (since) async {
        // B 侧返回 A 未确认的 op。
        return await engineB.opsToPush('dev-a');
      },
      sender: (ops) async {
        await engineB.pullFromPeer('dev-a', (_) async => ops);
      },
    );

    expect((await repoA.listSessions()).length, 3, reason: 'A 有 B 的 bs1');
    expect((await repoB.listSessions()).length, 3, reason: 'B 有 A 的 s0/s1');
  });

  test('快照折叠：5001 条 op + 对端已确认 → 行数下降，增量仍可拉到最新状态', () async {
    // 构造大量 op：直接批量插 sync_ops（绕过 upsert 的逐条路径）。
    final batch = <SyncOpsCompanion>[];
    for (var i = 1; i <= 5100; i++) {
      batch.add(SyncOpsCompanion(
        opId: Value('op-$i'),
        deviceId: const Value('dev-a'),
        lamport: Value(i),
        entity: const Value('session'),
        entityId: Value('s${i % 5}'),
        opType: const Value('upsert'),
        fieldsJson: const Value('{}'),
        createdAt: Value(i),
      ));
    }
    await dbA.batch((b) => b.insertAll(dbA.syncOps, batch));
    expect(await dbA.syncOpsCount(), 5100);

    // 对端已确认到 5000。
    await SyncEngine(repo: repoA, localDeviceId: 'dev-a')
        .pullFromPeer('dev-a', (since) async => []);
    // 直接写 peer_state acked=5000（模拟 B ack）。
    // sent 也必须到 5000：ack 的前提是这些 op **已经推出去过**，foldIfNeeded
    // 会同时校验 sent/acked 两个水位线，只写 acked 属于不完整的夹具。
    await dbA.into(dbA.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b',
          sentLamport: const Value(5000),
          ackedLamport: const Value(5000),
        ));

    final maintainer = SnapshotMaintainer(repoA, threshold: 5000);
    final folded = await maintainer.foldIfNeeded();

    expect(folded, 5000, reason: '已确认的 5000 条被折叠');
    final after = await dbA.syncOpsCount();
    expect(after, lessThan(5100), reason: '行数下降');
    expect(after, 101, reason: '5100-5000+1(snapshot)'); // 100 余量 + 快照

    // 增量拉取仍能拿到「最新状态」：剩余 op + snapshot 均可拉。
    // B 的 acked=5000 → 拉到 lamport > 5000 的剩余 op 与 snapshot(lamport=5000?)。
    // snapshot op 的 lamport = watermark(5000)，与 acked 相等 → B 已见过。
    final remaining = await dbA.customSelect(
      'SELECT COUNT(*) AS c FROM sync_ops WHERE lamport > 5000',
      readsFrom: {dbA.syncOps},
    ).get();
    expect(remaining.first.read<int>('c'), 100);

    // bootstrap：新设备导入快照后水位即对齐。
    final snapshot = SyncSnapshot(
      sessions: await repoA.listSessions(),
      questions: const [],
      images: const [],
      devices: const [],
      watermark: 5000,
    );
    final maintainerB = SnapshotMaintainer(repoB, threshold: 5000);
    await maintainerB.bootstrapFrom(snapshot, peerDeviceId: 'dev-a');
    final engineB2 = SyncEngine(repo: repoB, localDeviceId: 'dev-b');
    expect(await engineB2.ackedLamport('dev-a'), 5000,
        reason: 'bootstrap 后水位 = 快照水位，只走增量');
    // 增量拉取不重放历史（since=5000 起）。
    final ops = await engineB2.opsToPush('dev-a');
    expect(ops.every((o) => o.lamport > 5000 || o.entity == SyncEntity.snapshot),
        isTrue);
  });

  test('快照折叠未触发：ops 未超阈值', () async {
    await seedA(10);
    final folded = await SnapshotMaintainer(repoA, threshold: 5000).foldIfNeeded();
    expect(folded, 0);
  });

  test('快照折叠未触发：对端未确认', () async {
    final batch = <SyncOpsCompanion>[
      for (var i = 1; i <= 5010; i++)
        SyncOpsCompanion(
          opId: Value('op-$i'),
          deviceId: const Value('dev-a'),
          lamport: Value(i),
          entity: const Value('session'),
          entityId: const Value('x'),
          opType: const Value('upsert'),
          fieldsJson: const Value('{}'),
          createdAt: Value(i),
        )
    ];
    await dbA.batch((b) => b.insertAll(dbA.syncOps, batch));
    // peer_state acked 落后于最旧 op。
    await dbA.into(dbA.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b',
          ackedLamport: const Value(0),
        ));
    final folded = await SnapshotMaintainer(repoA, threshold: 5000).foldIfNeeded();
    expect(folded, 0, reason: '所有对端未确认 → 不得折叠');
  });

  test('快照折叠未触发：对端确认了但本机还没推出去（sent 落后）', () async {
    final batch = <SyncOpsCompanion>[
      for (var i = 1; i <= 5010; i++)
        SyncOpsCompanion(
          opId: Value('op-$i'),
          deviceId: const Value('dev-a'),
          lamport: Value(i),
          entity: const Value('session'),
          entityId: const Value('y'),
          opType: const Value('upsert'),
          fieldsJson: const Value('{}'),
          createdAt: Value(i),
        )
    ];
    await dbA.batch((b) => b.insertAll(dbA.syncOps, batch));
    // 只有 acked 水位线（例如对端 ack 的是别的方向），sent 还是 0：
    // 折叠会删掉从未推送出去的本地 op = 永久丢失，必须拒绝。
    await dbA.into(dbA.peerStates).insert(PeerStatesCompanion.insert(
          peerDeviceId: 'dev-b',
          ackedLamport: const Value(5000),
        ));
    final folded = await SnapshotMaintainer(repoA, threshold: 5000).foldIfNeeded();
    expect(folded, 0, reason: 'op 尚未推送（sent=0）→ 不得折叠');
    expect(await dbA.syncOpsCount(), 5010, reason: '本地 op 一条都不能少');
  });

  test('拉取游标不再写入 acked_lamport（保留未推送的本地 op）', () async {
    await seedA(2);
    final engine = SyncEngine(repo: repoA, localDeviceId: 'dev-a');
    // 对端有一条 lamport=100 的 op 被拉下来。
    await engine.pullFromPeer('dev-b', (since) async => [
          SyncOp(
            opId: 'remote-100',
            deviceId: 'dev-b',
            lamport: 100,
            entity: SyncEntity.session,
            entityId: 's-remote',
            opType: SyncOpType.upsert,
            fields: const {'status': 'done'},
            createdAt: 100,
          )
        ]);
    expect(await engine.ackedLamport('dev-b'), 0,
        reason: '拉取不等于对端确认，不得推进 acked');
    // 第二次拉取从水位继续（内存游标以 settings 表为准）。
    final seen = <int>[];
    await engine.pullFromPeer('dev-b', (since) async {
      seen.add(since);
      return const [];
    });
    expect(seen.single, 100, reason: '拉取游标必须持久化并继续生效');
  });
}
