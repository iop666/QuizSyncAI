import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show Expression, OrderingTerm, Value;
import 'package:quizsync_core/quizsync_core.dart';


/// 服务端任务执行器（M4 任务 3）：**串行**执行分析（默认并发 1，
/// 避免打爆 AI 限流），任务状态机 `queued → analyzing → done/failed`。
class ServerTaskExecutor {
  final CoreRepository repo;
  final AnalysisEngine engine;
  final ImageFileStore imageStore;

  /// 宿主提供的 AI 配置（含 API Key）；为 null 表示未配置。
  /// 每次执行任务时实时取配置（FutureOr：允许桌面端异步读 DPAPI Key）。
  final FutureOr<AiConfig?> Function() configProvider;

  /// 状态变化回调（服务端转发 WS task_update）。启动时由服务端注入。
  void Function(String taskId, String status, String? sessionId)?
      onTaskUpdate;

  final int Function() now;

  bool _running = false;

  ServerTaskExecutor({
    required this.repo,
    required this.engine,
    required this.imageStore,
    required this.configProvider,
    this.onTaskUpdate,
    int Function()? now,
  }) : now = now ?? nowMs;

  /// 创建（幂等）并调度一个分析任务。
  /// 返回 (task 状态, session_id)。
  ///
  /// [imageHashes] 是**多页**页序（用户需求 4，1..6 张）；为空时按单页
  /// [imageHash] 处理。多页任务的会话首页仍是 `imageHash`（= `imageHashes[0]`），
  /// 完整页序落在 `session_images` 表。
  Future<(String, String?)> submit({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    List<String>? imageHashes,
    String? collectionId,
    bool forceReanalyze = false,
  }) async {
    final hashes = (imageHashes == null || imageHashes.isEmpty)
        ? <String>[imageHash]
        : List<String>.from(imageHashes);
    final existing = await (repo.db.select(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .getSingleOrNull();
    if (existing != null) {
      // 幂等：重复提交直接返回既有状态。
      if (existing.status == 'queued' || existing.status == 'analyzing') {
        _kick();
      }
      return (existing.status, existing.sessionId);
    }

    // 同 hash 已有 done 会话且不强制 → 立即复用（protocol.md 3.3）。
    // 多页必须**页序完全一致**才算命中，否则「首页相同、后续页不同」会被
    // 错误复用成另一组题目的结果。
    if (!forceReanalyze) {
      final candidates = (await repo.listSessions(limit: 500))
          .where((s) => s.imageHash == imageHash && s.status == TaskState.done);
      for (final s in candidates) {
        final pages = await repo.imageHashesOf(s.sessionId);
        if (pages.length == hashes.length &&
            List.generate(pages.length, (i) => pages[i] == hashes[i])
                .every((same) => same)) {
          await repo.db.into(repo.db.tasks).insert(TasksCompanion(
                taskId: Value(taskId),
                imageHash: Value(imageHash),
                sourceDevice: Value(sourceDevice),
                status: const Value('done'),
                sessionId: Value(s.sessionId),
                createdAt: Value(now()),
                finishedAt: Value(now()),
              ));
          return ('done', s.sessionId);
        }
      }
    }

    final sessionId = newUuidV4();
    await repo.db.into(repo.db.tasks).insert(TasksCompanion(
          taskId: Value(taskId),
          imageHash: Value(imageHash),
          sourceDevice: Value(sourceDevice),
          status: const Value('queued'),
          sessionId: Value(sessionId),
          createdAt: Value(now()),
        ));
    await repo.upsertSession(Session(
      sessionId: sessionId,
      taskId: taskId,
      collectionId: collectionId,
      imageHash: imageHash,
      sourceDevice: sourceDevice,
      status: TaskState.queued,
      createdAt: now(),
      updatedAt: now(),
      updatedBy: repo.deviceId,
    ));
    await repo.setSessionImages(sessionId, hashes);
    onTaskUpdate?.call(taskId, 'queued', sessionId);
    _kick();
    return ('queued', sessionId);
  }

  /// 「重新生成」（用户需求 7）：按既有会话的页序重新跑一次（强制调 AI，
  /// 不复用缓存），返回新任务。
  ///
  /// 返回值带上 `taskId`：调用方（`/sessions/<id>/reanalyze`）要把任务号回给
  /// 客户端，而任务号是在这里生成的 —— 不回传的话客户端只能拿到空串
  /// （安卓结果页的「重新生成」就卡在这上面）。
  Future<({String status, String? sessionId, String taskId})> reanalyze({
    required String sessionId,
    required String sourceDevice,
  }) async {
    final session = await repo.getSession(sessionId, includeDeleted: true);
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final hashes = await repo.imageHashesOf(sessionId);
    if (hashes.isEmpty) {
      throw StateError('session has no image: $sessionId');
    }
    final taskId = newUuidV4();
    final (status, newSessionId) = await submit(
      taskId: taskId,
      imageHash: hashes.first,
      imageHashes: hashes,
      sourceDevice: sourceDevice,
      collectionId: session.collectionId,
      forceReanalyze: true,
    );
    return (status: status, sessionId: newSessionId, taskId: taskId);
  }

  Future<void> retry(String taskId) async {
    await (repo.db.update(repo.db.tasks)
          ..where((t) => Expression.and([
            t.taskId.equals(taskId),
            t.status.equals('failed'),
          ])))
        .write(TasksCompanion(status: const Value('queued'), errorCode: const Value(null)));
    _kick();
  }

  void _kick() {
    if (_running) return;
    _running = true;
    Future(_drain);
  }

  Future<void> _drain() async {
    try {
      while (true) {
        final next = await (repo.db.select(repo.db.tasks)
              ..where((t) => t.status.equals('queued'))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(1))
            .get();
        if (next.isEmpty) break;
        final task = next.single;
        try {
          await _execute(task);
        } catch (e) {
          await _finish(task.taskId, 'failed', 'internal', '内部错误: $e');
        }
      }
    } finally {
      _running = false;
    }
    // 关闭竞态窗口：`submit()` 可能在上面最后一个 SELECT 返回空之后、`_running`
    // 复位之前插入任务，此时它的 `_kick()` 看到 _running=true 直接返回，任务会
    // 永远停在 queued（手机端表现为轮询到超时）。退出前再确认一次。
    if (await _hasQueued()) _kick();
  }

  Future<bool> _hasQueued() async {
    final rows = await (repo.db.select(repo.db.tasks)
          ..where((t) => t.status.equals('queued'))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<void> _execute(TaskRow task) async {
    final config = await configProvider();
    if (config == null || config.apiKey.isEmpty || config.model.isEmpty) {
      await _finish(task.taskId, 'failed', 'ai_auth', '主机尚未配置 AI');
      return;
    }

    await (repo.db.update(repo.db.tasks)
          ..where((t) => t.taskId.equals(task.taskId)))
        .write(TasksCompanion(status: const Value('analyzing'), startedAt: Value(now())));
    final session = task.sessionId == null
        ? null
        : await repo.getSession(task.sessionId!, includeDeleted: true);
    if (session != null) {
      await repo.upsertSession(session.copyWith(status: TaskState.analyzing));
    }
    onTaskUpdate?.call(task.taskId, 'analyzing', task.sessionId);

    final bytes = await imageStore.read(task.imageHash);
    if (bytes == null) {
      await _finish(task.taskId, 'failed', 'internal', '图片文件缺失');
      return;
    }

    // 多页（用户需求 4）：按页序把全部图片一起送给 AI，让它把跨页的
    // 题干与选项合并成同一道题。缺任何一页都算失败（宁可重试也不要
    // 用残缺的页序得出错误答案）。
    final pageHashes = task.sessionId == null
        ? <String>[task.imageHash]
        : await repo.imageHashesOf(task.sessionId!);
    final ordered = pageHashes.isEmpty ? <String>[task.imageHash] : pageHashes;
    final bytesList = <Uint8List>[];
    for (final hash in ordered) {
      final b = hash == task.imageHash ? bytes : await imageStore.read(hash);
      if (b == null) {
        await _finish(task.taskId, 'failed', 'internal', '第 ${bytesList.length + 1} 页图片文件缺失');
        return;
      }
      bytesList.add(b);
    }

    // useCache:false —— submit() 已经做过「同图直接复用」的判断，这里再回放缓存
    // 只会把**另一个会话**的题目（带原 questionId）写进本任务：upsert 会按主键
    // 把 session_id 还原成旧会话，新会话就成了 status=done / 0 道题，而且
    // force_reanalyze 永远调不到 AI（reviewer 已端到端复现）。
    final outcome = await engine.analyzeImages(
      jpegBytesList: bytesList,
      imageHash: task.imageHash,
      config: config,
      useCache: false,
    );

    if (outcome.ok) {
      await repo.applyAnalysisResult(
        sessionId: task.sessionId!,
        input: AnalysisResultInput(
          aiProvider: config.providerId,
          aiModel: config.model,
          promptVersion: computePromptVersion(),
          rawResponse: outcome.rawText,
          latencyMs: outcome.latencyMs,
          cached: outcome.fromCache,
          questions: outcome.questions
              .map((q) => q.copyWith(sessionId: task.sessionId!))
              .toList(),
        ),
      );
      await _finish(task.taskId, 'done', null, null);
      onTaskUpdate?.call(task.taskId, 'done', task.sessionId);
    } else {
      await _fail(task, outcome.errorCode ?? 'internal',
          outcome.errorMessage ?? '分析失败');
    }
  }

  Future<void> _fail(TaskRow task, String errorCode, String message) async {
    await _finish(task.taskId, 'failed', errorCode, message);
    onTaskUpdate?.call(task.taskId, 'failed', task.sessionId);
  }

  Future<void> _finish(
      String taskId, String status, String? errorCode, String? message) async {
    await (repo.db.update(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .write(TasksCompanion(
      status: Value(status),
      errorCode: Value(errorCode),
      finishedAt: Value(now()),
    ));
    final task = await (repo.db.select(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .getSingleOrNull();
    if (task?.sessionId != null) {
      final session =
          await repo.getSession(task!.sessionId!, includeDeleted: true);
      if (session != null) {
        await repo.upsertSession(session.copyWith(
          status: TaskState.parse(status),
          errorCode: errorCode,
          errorMessage: message,
        ));
      }
    }
  }
}

/// 任务视图（GET /api/v1/tasks/{id} 的数据源）。
class TaskView {
  final String taskId;
  final String status;
  final String? sessionId;
  final String? errorCode;
  final String? errorMessage;

  const TaskView({
    required this.taskId,
    required this.status,
    this.sessionId,
    this.errorCode,
    this.errorMessage,
  });
}
