import '../model/sync_op.dart';
import '../util/ids.dart';
import 'lamport_clock.dart';

/// 每次本地 upsert / delete 恰好生成 1 条 op，`fields_json` 只含变更字段。
/// [persist] 由数据库层提供，保证 op 与业务行在同一事务内落库。
class SyncOpWriter {
  final String deviceId;
  final LamportClock clock;
  final Future<void> Function(SyncOp op) persist;

  SyncOpWriter({
    required this.deviceId,
    required this.clock,
    required this.persist,
  });

  Future<SyncOp> upsert({
    required SyncEntity entity,
    required String entityId,
    required Map<String, dynamic> changedFields,
    int? now,
  }) async {
    final op = SyncOp(
      opId: newUuidV4(),
      deviceId: deviceId,
      lamport: clock.tick(),
      entity: entity,
      entityId: entityId,
      opType: SyncOpType.upsert,
      fields: Map<String, dynamic>.from(changedFields),
      createdAt: now ?? nowMs(),
    );
    await persist(op);
    return op;
  }

  Future<SyncOp> delete({
    required SyncEntity entity,
    required String entityId,
    int? now,
  }) async {
    final ts = now ?? nowMs();
    final op = SyncOp(
      opId: newUuidV4(),
      deviceId: deviceId,
      lamport: clock.tick(),
      entity: entity,
      entityId: entityId,
      opType: SyncOpType.delete,
      fields: {'deleted_at': ts},
      createdAt: ts,
    );
    await persist(op);
    return op;
  }
}

/// 计算 [after] 相对 [before] 的变更字段（只含真正变化的键）。
/// [before] 为 null（新建行）时返回 after 的全部字段。
Map<String, dynamic> diffFields(
  Map<String, dynamic>? before,
  Map<String, dynamic> after,
) {
  if (before == null) return Map<String, dynamic>.from(after);
  final changed = <String, dynamic>{};
  after.forEach((k, v) {
    if (!_eq(before[k], v)) changed[k] = v;
  });
  return changed;
}

bool _eq(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
