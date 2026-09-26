import 'package:drift/drift.dart' show Value, Variable;

import 'package:quizsync_core/quizsync_core.dart';

/// 同步引擎（data-model.md 2.5 / 2.6 / 2.7，M6 任务 1–3）：
/// - 推送：本地 `lamport > peer_state.sent_lamport` 的 op 推给对端，成功后更新水位线；
/// - 拉取：`since_lamport`（已 ack 水位）+ `from_device` 分页拉（每页 500）；
/// - 断线重连：**先拉后推**，避免缺口；
/// - ack：对端确认 → 更新 `acked_lamport`；
/// - 快照折叠与 tombstone GC 见 [SnapshotMaintainer] / [tombstoneGc]。
class SyncEngine {
  final CoreRepository repo;
  final String localDeviceId;

  SyncEngine({required this.repo, required this.localDeviceId});

  /// 待推送 op（按 lamport 升序）。
  /// 只推**本机产生**的 op：sync_ops 里也存着从对端拉来并转存的 op
  /// （device_id 保留原值），不过滤就会把对端的 op 再推回去——sent 水位线
  /// 被外来的 lamport 顶高、计数虚高，且每次同步都在重传对端历史。
  Future<List<SyncOp>> opsToPush(String peerDeviceId, {int limit = 500}) async {
    final sent = await _sentLamport(peerDeviceId);
    final rows = await repo.db.customSelect(
      'SELECT * FROM sync_ops WHERE device_id = ? AND lamport > ? '
      'ORDER BY lamport ASC LIMIT ?',
      variables: [
        Variable.withString(localDeviceId),
        Variable.withInt(sent),
        Variable.withInt(limit),
      ],
      readsFrom: {repo.db.syncOps},
    ).get();
    return rows
        .map((r) => opFromRow(SyncOpRow(
              opId: r.read<String>('op_id'),
              deviceId: r.read<String>('device_id'),
              lamport: r.read<int>('lamport'),
              entity: r.read<String>('entity'),
              entityId: r.read<String>('entity_id'),
              opType: r.read<String>('op_type'),
              fieldsJson: r.read<String>('fields_json'),
              createdAt: r.read<int>('created_at'),
            )))
        .toList();
  }

  Future<int> _sentLamport(String peerId) async {
    final row = await (repo.db.select(repo.db.peerStates)
          ..where((t) => t.peerDeviceId.equals(peerId)))
        .getSingleOrNull();
    return row?.sentLamport ?? 0;
  }

  /// 拉取游标（本机已从该对端拉到的最大 lamport）。
  ///
  /// **不是** `acked_lamport`：契约里 acked 的含义是「对端已确认收到我的 op」，
  /// 而拉取游标是「我已收到对端的 op」。原来把拉取游标写进 acked_lamport，
  /// 会让 foldIfNeeded 以为对端确认过一切，从而删掉**从未推送出去**的本地 op
  /// （reviewer 已复现：2 条未推送 op 被折叠删除 = 永久丢失）。
  /// 该游标属于本机协调状态，存 settings 表（schemaVersion 固定为 1，不加列）。
  Future<int> _pullCursor(String peerId) async {
    final raw = await repo.getSetting('pull_cursor:$peerId');
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> _setPullCursor(String peerId, int lamport) =>
      repo.setSetting('pull_cursor:$peerId', lamport.toString());

  /// 对端确认收到本机 op 到 [lamport]（WS ack / bootstrap 时调用）。
  Future<void> onPeerAck(String peerId, int lamport) =>
      _upsertPeer(peerId, ackedLamport: lamport, lastSyncAt: nowMs());

  Future<int> ackedLamport(String peerId) async {
    final row = await (repo.db.select(repo.db.peerStates)
          ..where((t) => t.peerDeviceId.equals(peerId)))
        .getSingleOrNull();
    return row?.ackedLamport ?? 0;
  }

  /// 推送一批 op 给对端并推进 sent 水位线。
  /// [sender] 由调用方提供（Api 或 WS），返回实际送出的数量。
  Future<int> pushToPeer(
    String peerDeviceId,
    Future<void> Function(List<SyncOp> ops) sender,
  ) async {
    final ops = await opsToPush(peerDeviceId);
    if (ops.isEmpty) return 0;
    await sender(ops);
    await _upsertPeer(peerDeviceId,
        sentLamport: ops.last.lamport, lastSyncAt: nowMs());
    return ops.length;
  }

  /// 拉取并应用对端 op（先拉），返回应用数量（非重复）。
  Future<int> pullFromPeer(
    String peerDeviceId,
    Future<List<SyncOp>> Function(int sinceLamport) fetcher,
  ) async {
    final since = await _pullCursor(peerDeviceId);
    final ops = await fetcher(since);
    var applied = 0;
    var watermark = since;
    for (final op in ops) {
      final r = await repo.applyRemoteOp(op);
      if (!r.duplicate) applied++;
      if (op.lamport > watermark) watermark = op.lamport;
    }
    if (watermark > since) {
      // 只推进拉取游标；acked 只能由真实 ack 推进（见 onPeerAck）。
      await _setPullCursor(peerDeviceId, watermark);
      await _upsertPeer(peerDeviceId, lastSyncAt: nowMs());
    }
    return applied;
  }

  /// 断线重连后的完整序列：先拉后推（data-model.md 2.5）。
  Future<({int pulled, int pushed})> reconcile(
    String peerDeviceId, {
    required Future<List<SyncOp>> Function(int sinceLamport) fetcher,
    required Future<void> Function(List<SyncOp> ops) sender,
  }) async {
    final pulled = await pullFromPeer(peerDeviceId, fetcher);
    final pushed = await pushToPeer(peerDeviceId, sender);
    return (pulled: pulled, pushed: pushed);
  }

  Future<void> _upsertPeer(String peerId,
      {int? sentLamport, int? ackedLamport, int? lastSyncAt}) async {
    final existing = await (repo.db.select(repo.db.peerStates)
          ..where((t) => t.peerDeviceId.equals(peerId)))
        .getSingleOrNull();
    if (existing == null) {
      await repo.db.into(repo.db.peerStates).insert(PeerStatesCompanion.insert(
            peerDeviceId: peerId,
            sentLamport: Value(sentLamport ?? 0),
            ackedLamport: Value(ackedLamport ?? 0),
            lastSyncAt: Value(lastSyncAt),
          ));
    } else {
      await (repo.db.update(repo.db.peerStates)
            ..where((t) => t.peerDeviceId.equals(peerId)))
          .write(PeerStatesCompanion(
        sentLamport: Value(
            sentLamport != null && sentLamport > existing.sentLamport
                ? sentLamport
                : existing.sentLamport),
        ackedLamport: Value(
            ackedLamport != null && ackedLamport > existing.ackedLamport
                ? ackedLamport
                : existing.ackedLamport),
        lastSyncAt: Value(lastSyncAt ?? existing.lastSyncAt),
      ));
    }
  }
}

/// 快照折叠与新设备 bootstrap（data-model.md 2.6）。
class SnapshotMaintainer {
  final CoreRepository repo;
  final int threshold;

  SnapshotMaintainer(this.repo, {this.threshold = 5000});

  /// 触发条件：单个 device 的 ops > [threshold]，且所有对端的
  /// acked_lamport 已越过其中最早一批（这里取全局最小 ack 与最旧 op 比较）。
  /// 动作：删除已确认 op，写入一条 `snapshot` op（payload=水位）。
  /// 返回折叠掉的行数（0 = 未触发）。
  Future<int> foldIfNeeded() async {
    final total = await repo.db.syncOpsCount();
    if (total <= threshold) return 0;

    final oldestRow = await repo.db.customSelect(
      'SELECT MIN(lamport) AS m FROM sync_ops',
      readsFrom: {repo.db.syncOps},
    ).get();
    final oldest = oldestRow.first.readNullable<int>('m');
    if (oldest == null) return 0;

    // 所有对端（有 peer_state 记录的）的 acked 必须都越过最旧 op。
    final peers = await repo.db.select(repo.db.peerStates).get();
    if (peers.isEmpty) return 0;
    final minAck = peers.map((p) => p.ackedLamport).reduce((a, b) => a < b ? a : b);
    final minSent =
        peers.map((p) => p.sentLamport).reduce((a, b) => a < b ? a : b);
    if (minAck < oldest || minSent < oldest) return 0;

    // 折叠到两个水位线的较小值：opus 必须既已**发出**（sent）也已被**确认**
    // （acked），否则删掉的就是还没送到对端的数据（原实现只比 acked，
    // 而 acked 在 pullFromPeer 里被当成拉取游标写高 → 未推送的本地 op 被删）。
    final watermark = minAck < minSent ? minAck : minSent;
    if (watermark <= 0) return 0;

    final folded = await repo.db.customSelect(
      'SELECT COUNT(*) AS c FROM sync_ops WHERE lamport <= ?',
      variables: [Variable.withInt(watermark)],
      readsFrom: {repo.db.syncOps},
    ).get();
    final count = folded.first.read<int>('c');
    if (count == 0) return 0;

    await repo.db.transaction(() async {
      await repo.db.customUpdate(
        'DELETE FROM sync_ops WHERE lamport <= ?',
        variables: [Variable.withInt(watermark)],
        updates: {repo.db.syncOps},
      );
      // 快照本身保留最近一次即可：先删旧快照。
      await repo.db.customUpdate(
        "DELETE FROM sync_ops WHERE entity = 'snapshot'",
        variables: const [],
        updates: {repo.db.syncOps},
      );
      await repo.db.into(repo.db.syncOps).insert(SyncOpsCompanion(
            opId: Value(newUuidV4()),
            deviceId: Value(repo.deviceId),
            lamport: Value(watermark),
            entity: const Value('snapshot'),
            entityId: const Value('global'),
            opType: const Value('upsert'),
            fieldsJson: Value('{"watermark":$watermark}'),
            createdAt: Value(nowMs()),
          ));
    });
    return count;
  }

  /// 新设备 bootstrap：全量快照导入后把对端水位线设为快照水位。
  /// **不通过重放全部历史 op 来 bootstrap。**
  Future<void> bootstrapFrom(
    SyncSnapshot snapshot, {
    required String peerDeviceId,
  }) async {
    for (final s in snapshot.sessions) {
      await repo.upsertSession(s);
    }
    for (final q in snapshot.questions) {
      await repo.upsertQuestion(q);
    }
    for (final img in snapshot.images) {
      final local = await repo.getImage(img.hash);
      await repo.upsertImage(local ?? img);
    }
    for (final d in snapshot.devices) {
      await repo.upsertDevice(d);
    }
    await SyncEngine(repo: repo, localDeviceId: repo.deviceId)._upsertPeer(
      peerDeviceId,
      ackedLamport: snapshot.watermark,
      sentLamport: snapshot.watermark,
      lastSyncAt: nowMs(),
    );
  }
}

class SyncSnapshot {
  final List<Session> sessions;
  final List<Question> questions;
  final List<ImageMeta> images;
  final List<DeviceInfo> devices;
  final int watermark;

  const SyncSnapshot({
    required this.sessions,
    required this.questions,
    required this.images,
    required this.devices,
    required this.watermark,
  });
}

/// Tombstone 物理清理（data-model.md 2.7）：
/// `deleted_at` 距今 > 30 天，且所有对端 acked_lamport 已越过该删除 op。
/// 返回清理行数。
Future<int> tombstoneGc(CoreRepository repo,
    {Duration ttl = const Duration(days: 30), int Function()? now}) async {
  final ts = (now ?? nowMs)();
  final cutoff = ts - ttl.inMilliseconds;

  final peers = await repo.db.select(repo.db.peerStates).get();
  final minAck = peers.isEmpty
      ? null
      : peers.map((p) => p.ackedLamport).reduce((a, b) => a < b ? a : b);

  var removed = 0;
  // sessions
  final oldSessions = await repo.db.customSelect(
    'SELECT session_id FROM sessions WHERE deleted_at IS NOT NULL AND deleted_at < ?',
    variables: [Variable.withInt(cutoff)],
    readsFrom: {repo.db.sessions},
  ).get();
  for (final row in oldSessions) {
    final id = row.read<String>('session_id');
    if (minAck != null && !await _deleteAckedBy(repo, 'session', id, minAck)) continue;
    await repo.db.customUpdate(
      'DELETE FROM sessions WHERE session_id = ?',
      variables: [Variable.withString(id)],
      updates: {repo.db.sessions},
    );
    removed++;
  }

  // questions（FTS 由触发器同步删除）
  final oldQuestions = await repo.db.customSelect(
    'SELECT question_id FROM questions WHERE deleted_at IS NOT NULL AND deleted_at < ?',
    variables: [Variable.withInt(cutoff)],
    readsFrom: {repo.db.questions},
  ).get();
  for (final row in oldQuestions) {
    final id = row.read<String>('question_id');
    if (minAck != null && !await _deleteAckedBy(repo, 'question', id, minAck)) continue;
    await repo.db.customUpdate(
      'DELETE FROM questions WHERE question_id = ?',
      variables: [Variable.withString(id)],
      updates: {repo.db.questions},
    );
    removed++;
  }
  return removed;
}

/// 该实体是否已被所有对端确认：实体的**全部** op（含 delete 与携带
/// deleted_at 的 upsert）的 lamport 均 ≤ minAck。
Future<bool> _deleteAckedBy(
    CoreRepository repo, String entity, String entityId, int minAck) async {
  final rows = await repo.db.customSelect(
    'SELECT MAX(lamport) AS m FROM sync_ops WHERE entity = ? AND entity_id = ?',
    variables: [Variable.withString(entity), Variable.withString(entityId)],
    readsFrom: {repo.db.syncOps},
  ).get();
  final maxLamport = rows.first.readNullable<int>('m');
  if (maxLamport == null) return true;
  return maxLamport <= minAck;
}

/// 缺文件的图片（后台补传用，data-model.md 2.4）。
Future<List<ImageMeta>> imagesMissingFile(CoreRepository repo,
    {int recentLimit = 200}) async {
  final rows = await repo.db.customSelect(
    'SELECT * FROM images WHERE local_path IS NULL '
    'ORDER BY created_at DESC LIMIT ?',
    variables: [Variable.withInt(recentLimit)],
    readsFrom: {repo.db.images},
  ).get();
  return rows
      .map((r) => imageFromRow(ImageRow(
            hash: r.read<String>('hash'),
            size: r.read<int>('size'),
            mime: r.read<String>('mime'),
            width: r.readNullable<int>('width'),
            height: r.readNullable<int>('height'),
            localPath: r.readNullable<String>('local_path'),
            createdAt: r.read<int>('created_at'),
            uploadedBy: r.read<String>('uploaded_by'),
          )))
      .toList();
}

/// 本地文件清理：超过 [maxFiles] 时删最旧文件并把 local_path 置 NULL
/// （文本结果与元数据永久保留）。[onDelete] 由宿主注入真正的删除动作
/// （同步层保持无 I/O）；为 null 时只断开关联，磁盘文件会残留。
/// [maxFiles] <= 0 表示**不设限**（用户需求 5）。
///
/// [keep] 里的 hash **永不删除**（M47）：安卓端离线队列里的任务补跑时必须能从
/// 磁盘取到原图，而队列上限（20 条）与本地上限（20 张）是同一个量级 ——
/// 按时间剪最旧会把队首任务的原图先剪掉，那条任务从此每次补跑都失败。
Future<int> pruneImageFiles(CoreRepository repo, String Function(String hash) pathOf,
    {int maxFiles = 200,
    Future<void> Function(String path)? onDelete,
    Set<String> keep = const {}}) async {
  if (maxFiles <= 0) return 0;
  final rows = await repo.db.customSelect(
    'SELECT hash FROM images WHERE local_path IS NOT NULL '
    'ORDER BY created_at ASC',
    variables: const [],
    readsFrom: {repo.db.images},
  ).get();
  final candidates = [
    for (final r in rows)
      if (!keep.contains(r.read<String>('hash'))) r.read<String>('hash'),
  ];
  if (candidates.length <= maxFiles) return 0;
  final excess = candidates.length - maxFiles;
  for (var i = 0; i < excess; i++) {
    final hash = candidates[i];
    final path = pathOf(hash);
    if (onDelete != null) {
      try {
        await onDelete(path);
      } catch (_) {
        // 删除失败（占用/权限）也要断开关联，避免每轮重复尝试。
      }
    }
    await repo.setImageLocalPath(hash, null);
  }
  return excess;
}
