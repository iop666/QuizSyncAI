import 'package:drift/drift.dart' show Variable;

import '../db/database.dart';
import '../util/ids.dart';

/// 每日配额（`ai-contract.md` 第 4 节）：
/// 默认 200 次真实调用（**不含缓存命中**）；达到上限明确提示，不静默失败。
/// 每次真实调用记录到 `ai_usage` 表。
///
/// M44 第 2 条（用户要求）：[dailyLimit] **≤ 0 表示不设上限** —— 仍然照常记录用量
/// （统计用），但永不拦住调用。
class QuotaGuard {
  final QuizSyncDb db;
  final int dailyLimit;
  final int Function() now;

  QuotaGuard(this.db, {this.dailyLimit = 200, int Function()? now})
      : now = now ?? nowMs;

  /// 是否「不设上限」（设置里选的那一项）。
  bool get unlimited => dailyLimit <= 0;

  DateTime _startOfToday() {
    final ts = DateTime.fromMillisecondsSinceEpoch(now());
    return DateTime(ts.year, ts.month, ts.day);
  }

  /// 今日已用量（按本机自然日）。
  Future<int> usedToday() async {
    final startMs = _startOfToday().millisecondsSinceEpoch;
    final rows = await db.customSelect(
      'SELECT COUNT(*) AS c FROM ai_usage WHERE called_at >= ?',
      variables: [Variable.withInt(startMs)],
      readsFrom: {db.aiUsage},
    ).get();
    return rows.first.read<int>('c');
  }

  Future<bool> get canCall async =>
      unlimited || await usedToday() < dailyLimit;

  Future<void> recordUsage({
    required String model,
    required String promptVersion,
    required String imageHash,
    required bool ok,
    String? errorCode,
    int? latencyMs,
  }) async {
    await db.into(db.aiUsage).insert(AiUsageRow(
          id: newUuidV4(),
          calledAt: now(),
          model: model,
          promptVersion: promptVersion,
          imageHash: imageHash,
          ok: ok,
          errorCode: errorCode,
          latencyMs: latencyMs,
        ));
  }
}
