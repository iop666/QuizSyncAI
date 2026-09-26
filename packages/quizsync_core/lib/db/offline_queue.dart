import 'dart:convert';

import 'package:drift/drift.dart';

import '../util/ids.dart';
import 'database.dart';

/// 离线队列已满（`data-model.md` 2.8：上限默认 20，超出拒绝入队）。
class QueueFullException implements Exception {
  final int maxQueued;
  QueueFullException(this.maxQueued);
  @override
  String toString() => '离线队列已满（$maxQueued），请等 Windows 上线后重试';
}

/// 「现在不能处理，但不是这条任务的问题」（例如主机还没选任务合集）：
/// 本轮停止，**不累加 attempts**。
///
/// 没有这个信号时，临时性阻塞（用户还没在电脑上选合集）会把队列里的任务
/// 一条条烧到 `queue_give_up` 死信，等合集选好了反而再也补跑不了。
class QueueRetryLater implements Exception {
  final String message;
  QueueRetryLater(this.message);
  @override
  String toString() => '稍后重试：$message';
}

/// 离线任务队列（`data-model.md` 2.8）。
///
/// tasks 表是本端协调状态，**不产生 sync_ops**（不随操作日志同步）。
class OfflineQueue {
  final QuizSyncDb db;
  final int maxQueued;

  /// 单条任务的最大补跑次数：超过则标记 failed 并跳过，避免一条坏任务
  /// （例如图片文件已不存在）把整条队列永久堵死、最后连入队都失败。
  final int maxAttempts;

  OfflineQueue(this.db, {this.maxQueued = 20, this.maxAttempts = 5});

  Future<int> queuedCount() async {
    final rows = await (db.select(db.tasks)
          ..where((t) => t.status.equals('queued')))
        .get();
    return rows.length;
  }

  Future<bool> get canEnqueue async => await queuedCount() < maxQueued;

  /// 入队。队满抛 [QueueFullException]（UI 转成用户提示，不静默丢弃）。
  /// 计数与插入放在同一事务里，避免并发入队越过上限。
  ///
  /// [imageHashes] / [collectionId] 会写进 `payload_json`：多页识别与合集
  /// 归属必须在离线补跑时原样复原（用户需求 4/8）。
  Future<TaskRow> enqueue({
    required String imageHash,
    required String sourceDevice,
    String? taskId,
    int? now,
    List<String>? imageHashes,
    String? collectionId,
  }) async {
    return db.transaction(() async {
      if (!await canEnqueue) throw QueueFullException(maxQueued);
      final payload = <String, dynamic>{
        if (imageHashes != null && imageHashes.isNotEmpty)
          'image_hashes': imageHashes,
        if (collectionId != null && collectionId.isNotEmpty)
          'collection_id': collectionId,
      };
      final row = TaskRow(
        taskId: taskId ?? newUuidV4(),
        imageHash: imageHash,
        sourceDevice: sourceDevice,
        status: 'queued',
        attempts: 0,
        errorCode: null,
        sessionId: null,
        createdAt: now ?? nowMs(),
        startedAt: null,
        finishedAt: null,
        payloadJson: payload.isEmpty ? null : jsonEncode(payload),
      );
      await db.into(db.tasks).insert(row);
      return row;
    });
  }

  /// 解析 [enqueue] 写入的额外参数。
  static ({List<String> imageHashes, String? collectionId}) parsePayload(
      TaskRow task) {
    final raw = task.payloadJson;
    if (raw == null || raw.isEmpty) {
      return (imageHashes: <String>[task.imageHash], collectionId: null);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final list = decoded['image_hashes'];
        return (
          imageHashes: list is List && list.isNotEmpty
              ? list.map((e) => e.toString()).toList()
              : <String>[task.imageHash],
          collectionId: decoded['collection_id']?.toString(),
        );
      }
    } catch (_) {}
    return (imageHashes: <String>[task.imageHash], collectionId: null);
  }

  Future<List<TaskRow>> queuedTasks() async {
    return (db.select(db.tasks)
          ..where((t) => t.status.equals('queued'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// 按入队顺序补跑。
  ///
  /// [process] 返回 true 表示该任务已成功提交（置 done）；
  /// 返回 false 或抛其他异常则本次停止，任务保持 queued、attempts+1，
  /// 等下一次上线事件再试。attempts 超过 [maxAttempts] 时该任务改判
  /// failed 并**继续处理后面的任务**（死信，不再阻塞整条队列）。
  /// 抛 [QueueRetryLater] 表示「现在整体不可用」（主机未选合集等）：
  /// 立即停止本轮且**不累加 attempts**，避免把好任务烧成死信。
  Future<int> drain(Future<bool> Function(TaskRow task) process) async {
    var processed = 0;
    for (final task in await queuedTasks()) {
      var ok = false;
      try {
        ok = await process(task);
      } on QueueRetryLater {
        break; // 整体不可用：保持 queued，等下次上线事件
      } catch (_) {
        ok = false;
      }
      if (ok) {
        await (db.update(db.tasks)..where((t) => t.taskId.equals(task.taskId)))
            .write(TasksCompanion(
          status: const Value('done'),
          finishedAt: Value(nowMs()),
        ));
        processed++;
        continue;
      }
      final attempts = task.attempts + 1;
      if (attempts >= maxAttempts) {
        await (db.update(db.tasks)..where((t) => t.taskId.equals(task.taskId)))
            .write(TasksCompanion(
          attempts: Value(attempts),
          status: const Value('failed'),
          errorCode: const Value('queue_give_up'),
          finishedAt: Value(nowMs()),
        ));
        continue; // 跳过这条坏任务，继续后面的
      }
      await _bumpAttempts(task.taskId, attempts);
      break; // 可能是对端不在线：本轮到此为止，等下次上线事件
    }
    return processed;
  }

  Future<void> _bumpAttempts(String taskId, int attempts) async {
    await (db.update(db.tasks)..where((t) => t.taskId.equals(taskId)))
        .write(TasksCompanion(attempts: Value(attempts)));
  }
}
