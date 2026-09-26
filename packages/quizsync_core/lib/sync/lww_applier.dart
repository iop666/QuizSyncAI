import '../model/sync_op.dart';
import 'field_clocks.dart';

/// 字段级 LWW 应用结果。
class LwwResult {
  /// 实际被写入的字段名集合（被更新的写入跳过的不在内）。
  final Set<String> appliedFields;

  /// 应用后的字段时钟表（新 Map，不改入参）。
  final Map<String, FieldClock> clocks;

  /// 行级 lamport / updated_by：所有字段时钟中的最大值。
  final int rowLamport;
  final String rowUpdatedBy;

  const LwwResult(this.appliedFields, this.clocks, this.rowLamport, this.rowUpdatedBy);
}

/// 按 `data-model.md` 2.2 的伪码实现字段级 LWW。
///
/// [currentRow]：该实体当前行的字段值（snake_case 列名 → 值），
/// 含 `lamport` / `updated_by` 两个行级基准字段；行不存在时传 null。
/// 应用成功会把被接受字段直接写回 [currentRow]。
class LwwApplier {
  static LwwResult apply({
    Map<String, dynamic>? currentRow,
    required Map<String, FieldClock> clocks,
    required SyncOp op,
  }) {
    final applied = <String>{};
    final newClocks = Map<String, FieldClock>.from(clocks);

    // 字段从未被单独记录过时，以该行的 lamport / updated_by 作为基准比较，
    // 即「整体写入」与「字段写入」可以正确比较先后。
    final FieldClock? baseline = currentRow == null
        ? null
        : FieldClock(
            (currentRow['lamport'] as num?)?.toInt() ?? 0,
            currentRow['updated_by']?.toString() ?? '',
          );

    // 删除 vs 修改的收敛（`data-model.md` 2.9 场景 7：**不得出现一端删一端在的
    // 永久分叉**）。规则：**lamport 大者赢，输的一方跟着改**。
    //
    // 删除是「往 `deleted_at` 写一个时间戳」，所以它天然参与字段级 LWW；问题在于
    // 输掉的那一端不会自己回头：A 离线删掉某条（lamport 低），B 同时改了它
    // （lamport 高）——B 按 LWW 拒掉删除（修改赢），而 A 端自己的墓碑**永远不会**
    // 被清掉，两端就此永久分叉。这里补上另一半：本行有墓碑、来的是**不含**
    // `deleted_at` 的 upsert、且这次写入比墓碑更新 → 墓碑作废（删除输，删除方
    // 跟着复活）。反过来删除的 lamport 更高时，收到删除的一端照旧落墓碑，两端
    // 都删 —— 两个方向都会收敛到同一个状态。
    if (currentRow != null && currentRow['deleted_at'] != null) {
      final tomb = newClocks['deleted_at'] ?? baseline;
      final incomingIsDelete =
          op.opType == SyncOpType.delete || op.fields.containsKey('deleted_at');
      if (!incomingIsDelete &&
          (tomb == null ||
              compareVersions(op.lamport, op.deviceId, tomb.l, tomb.d) > 0)) {
        currentRow['deleted_at'] = null;
        newClocks['deleted_at'] = FieldClock(op.lamport, op.deviceId);
        applied.add('deleted_at');
      }
    }

    for (final entry in op.fields.entries) {
      final f = entry.key;
      final cur = newClocks[f] ?? baseline;
      if (cur != null &&
          compareVersions(op.lamport, op.deviceId, cur.l, cur.d) <= 0) {
        continue; // 已有更新的写入
      }
      if (currentRow != null) {
        currentRow[f] = entry.value;
      }
      newClocks[f] = FieldClock(op.lamport, op.deviceId);
      applied.add(f);
    }

    // 行级 lamport / updated_by 更新为所有字段时钟中的最大值。
    var rowLamport = (currentRow?['lamport'] as num?)?.toInt() ?? 0;
    var rowUpdatedBy = currentRow?['updated_by']?.toString() ?? '';
    for (final fc in newClocks.values) {
      if (compareVersions(fc.l, fc.d, rowLamport, rowUpdatedBy) > 0) {
        rowLamport = fc.l;
        rowUpdatedBy = fc.d;
      }
    }

    return LwwResult(applied, newClocks, rowLamport, rowUpdatedBy);
  }
}
