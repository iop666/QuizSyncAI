import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:quizsync_core/quizsync_core.dart';

/// 一页待分析的图片（用户需求 4：多页题目一次识别）。
class WorkflowPage {
  final Uint8List jpeg;
  final int width;
  final int height;
  final String hash;

  const WorkflowPage({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.hash,
  });
}

/// 桌面端单机分析工作流（M3 任务 6）：
/// 入库 → 建任务 → 调 AI（AnalysisEngine）→ 解析 → 写题目 → 生成 sync_ops。
/// 完全平台无关：单测用内存库 + FakeAiProvider 驱动整条链路。
class AnalysisWorkflow {
  final CoreRepository repo;
  final AnalysisEngine engine;
  final String deviceId;

  /// 「是否保存图片文件」由 UI 侧决定文件落盘，这里只收回调。
  Future<void> Function(String hash, Uint8List jpeg)? saveImageFile;

  /// 读取本机已保存的图片（多页会话「重新分析」时取回历史页）。
  Future<Uint8List?> Function(String hash)? readImageFile;

  /// 本地识别**开始**（用户反馈 2）：手机端据此显示「N 张图片识别中…」。
  void Function(String sessionId, int imageCount)? onSessionStarted;

  /// 本地识别**结束**：ok=true 表示已出结果（手机端会自动加载并显示）。
  void Function(String sessionId, bool ok)? onSessionFinished;

  AnalysisWorkflow({
    required this.repo,
    required this.engine,
    required this.deviceId,
    this.saveImageFile,
    this.readImageFile,
  });

  /// 提交一张已压缩的 JPEG 并执行分析（单页便捷入口）。
  /// 返回目标会话 id（新建，或同图去重命中的既有会话）。
  Future<WorkflowResult> run({
    required Uint8List jpeg,
    required String imageHash,
    required int width,
    required int height,
    required AiConfig config,
    String? taskId,
    String? collectionId,
    bool force = false,
  }) =>
      runMulti(
        pages: [
          WorkflowPage(jpeg: jpeg, width: width, height: height, hash: imageHash)
        ],
        config: config,
        taskId: taskId,
        collectionId: collectionId,
        force: force,
      );

  /// 多页入口（用户需求 4）：1..N 页图片作为**一次识别**提交。
  Future<WorkflowResult> runMulti({
    required List<WorkflowPage> pages,
    required AiConfig config,
    String? taskId,
    String? collectionId,
    bool force = false,
  }) async {
    if (pages.isEmpty) {
      return const WorkflowResult(
        sessionId: '',
        cached: false,
        errorCode: 'internal',
        errorMessage: '没有可分析的图片',
      );
    }
    final now = nowMs();
    final tid = taskId ?? newUuidV4();
    final sessionId = newUuidV4();
    final hashes = pages.map((p) => p.hash).toList();
    final first = pages.first;

    // 归属合集（用户需求 8）：显式传入优先，否则取当前选中的合集。
    final collection = (collectionId != null && collectionId.isNotEmpty)
        ? collectionId
        : await repo.getSetting(kActiveCollectionKey);

    // 0. 同图去重（ai-contract §4）：已有 done 会话 → 直接复用。
    //    必须在建图片/会话/任务**之前**判断：原实现先建会话再删，
    //    每次都多出「新建 + 删除」两条 op 并让列表闪一下。
    //    多页必须**页序完全一致**才算命中（首页相同、后续页不同是两组题）。
    if (!force) {
      final candidates = (await repo.listSessions(limit: 500))
          .where((s) => s.imageHash == first.hash && s.status == TaskState.done);
      for (final s in candidates) {
        final saved = await repo.imageHashesOf(s.sessionId);
        if (saved.length != hashes.length) continue;
        var same = true;
        for (var i = 0; i < saved.length; i++) {
          if (saved[i] != hashes[i]) {
            same = false;
            break;
          }
        }
        if (!same) continue;
        await repo.db.into(repo.db.tasks).insert(TasksCompanion(
              taskId: Value(tid),
              imageHash: Value(first.hash),
              sourceDevice: Value(deviceId),
              status: const Value('done'),
              sessionId: Value(s.sessionId),
              createdAt: Value(now),
              finishedAt: Value(now),
            ));
        return WorkflowResult(
          sessionId: s.sessionId,
          cached: true,
          message: '这道题之前搜过，跳到上次结果',
        );
      }
    }

    // 1. 图片元数据 + 会话 + 任务。
    for (final p in pages) {
      await repo.upsertImage(ImageMeta(
        hash: p.hash,
        size: p.jpeg.length,
        mime: 'image/jpeg',
        width: p.width,
        height: p.height,
        localPath: null,
        createdAt: now,
        uploadedBy: deviceId,
      ));
      if (saveImageFile != null) {
        try {
          await saveImageFile!(p.hash, p.jpeg);
        } catch (_) {
          // SPEC §8：磁盘空间不足 / 写入失败 → 结果优先，只提示图片未保存。
        }
      }
    }
    await repo.upsertSession(Session(
      sessionId: sessionId,
      taskId: tid,
      collectionId: collection,
      imageHash: first.hash,
      sourceDevice: deviceId,
      status: TaskState.analyzing,
      createdAt: now,
      updatedAt: now,
      updatedBy: deviceId,
    ));
    await repo.setSessionImages(sessionId, hashes);
    await repo.db.into(repo.db.tasks).insert(TasksCompanion(
          taskId: Value(tid),
          imageHash: Value(first.hash),
          sourceDevice: Value(deviceId),
          status: const Value('analyzing'),
          createdAt: Value(now),
          startedAt: Value(now),
          sessionId: Value(sessionId),
        ));

    // 2. 引擎 + 结果落库。
    onSessionStarted?.call(sessionId, pages.length);
    return _drive(
      sessionId: sessionId,
      taskId: tid,
      pages: pages,
      config: config,
      force: force,
    );
  }

  /// 失败会话的「重试」（SPEC §8）：复用同一会话与任务。
  ///
  /// 多页会话从本机已保存的图片里取回全部页；[jpeg] 作为首页兜底
  /// （裁掉过/换过图的情形）。缺少任何一页都抛 [StateError]，由 UI 提示。
  Future<WorkflowResult> retrySession({
    required String sessionId,
    required Uint8List jpeg,
    required AiConfig config,
    int? width,
    int? height,
  }) async {
    final sess = await repo.getSession(sessionId, includeDeleted: true);
    if (sess == null) throw StateError('session not found');
    final hashes = await repo.imageHashesOf(sessionId);
    final pages = <WorkflowPage>[];
    for (var i = 0; i < hashes.length; i++) {
      final hash = hashes[i];
      Uint8List? bytes;
      if (hash == sess.imageHash) {
        bytes = jpeg;
      } else if (readImageFile != null) {
        bytes = await readImageFile!(hash);
      }
      if (bytes == null) {
        throw StateError('第 ${i + 1} 页图片文件已不在本机，无法重新分析');
      }
      pages.add(WorkflowPage(
        jpeg: bytes,
        width: width ?? 0,
        height: height ?? 0,
        hash: hash,
      ));
    }
    await repo.upsertSession(sess.copyWith(
      status: TaskState.analyzing,
      errorCode: null,
      errorMessage: null,
      rawResponse: null,
      latencyMs: null,
    ));
    return _drive(
      sessionId: sessionId,
      taskId: sess.taskId,
      pages: pages,
      config: config,
      // 显式「重新分析」必须真的再问一次 AI，不能回放缓存。
      force: true,
    );
  }

  Future<WorkflowResult> _drive({
    required String sessionId,
    required String? taskId,
    required List<WorkflowPage> pages,
    required AiConfig config,
    required bool force,
  }) async {
    // 引擎：缓存 → 配额 → 网络重试 → 容错解析。
    final outcome = await engine.analyzeImages(
      jpegBytesList: pages.map((p) => p.jpeg).toList(),
      imageHash: pages.first.hash,
      config: config,
      useCache: !force,
    );

    // 用户在「识别中」页点过「取消」：丢弃本次结果，不要把它又写回去。
    // （原来取消只改状态，请求返回后照样覆盖成 done/failed，取消形同无效。）
    final afterRun = await repo.getSession(sessionId, includeDeleted: true);
    if (afterRun != null && afterRun.status == TaskState.cancelled) {
      if (taskId != null) {
        await _finishTask(taskId, 'cancelled', sessionId, 'cancelled');
      }
      onSessionFinished?.call(sessionId, false);
      return WorkflowResult(
        sessionId: sessionId,
        cached: false,
        errorCode: 'cancelled',
        errorMessage: '已取消本次分析',
      );
    }

    if (outcome.fromCache) {
      final cachedSid = outcome.cacheSessionId;
      if (cachedSid != null && cachedSid != sessionId) {
        await repo.deleteSession(sessionId);
        if (taskId != null) {
          await _finishTask(taskId, 'done', cachedSid);
        }
        // 临时会话已被删除：先把它标成结束（手机端不留「识别中」占位），
        // 再把真正复用的那个会话的完成状态推过去。
        onSessionFinished?.call(sessionId, true);
        onSessionFinished?.call(cachedSid, true);
        return WorkflowResult(
          sessionId: cachedSid,
          cached: true,
          message: '这道题之前搜过，跳到上次结果',
        );
      }
    }

    if (outcome.ok) {
      await repo.applyAnalysisResult(
        sessionId: sessionId,
        input: AnalysisResultInput(
          aiProvider: config.providerId,
          aiModel: config.model,
          promptVersion: computePromptVersion(),
          rawResponse: outcome.rawText,
          latencyMs: outcome.latencyMs,
          cached: outcome.fromCache,
          questions: outcome.questions
              .map((q) => q.copyWith(sessionId: sessionId))
              .toList(),
        ),
      );
      if (taskId != null) await _finishTask(taskId, 'done', sessionId);
      onSessionFinished?.call(sessionId, true);
      return WorkflowResult(sessionId: sessionId, cached: false);
    }

    // 失败：保留 raw_response / 图片，供「重试」。
    final sess = await repo.getSession(sessionId, includeDeleted: true);
    await repo.upsertSession(sess!.copyWith(
      status: TaskState.failed,
      errorCode: outcome.errorCode,
      errorMessage: outcome.errorMessage,
      rawResponse: outcome.rawText.isEmpty ? null : outcome.rawText,
      latencyMs: outcome.latencyMs,
    ));
    if (taskId != null) {
      await _finishTask(taskId, 'failed', sessionId, outcome.errorCode);
    }
    onSessionFinished?.call(sessionId, false);
    return WorkflowResult(
      sessionId: sessionId,
      cached: false,
      errorCode: outcome.errorCode,
      errorMessage: outcome.errorMessage,
    );
  }

  Future<void> _finishTask(String taskId, String status, String sessionId,
      [String? errorCode]) async {
    await (repo.db.update(repo.db.tasks)
          ..where((t) => t.taskId.equals(taskId)))
        .write(TasksCompanion(
      status: Value(status),
      sessionId: Value(sessionId),
      errorCode: Value(errorCode),
      finishedAt: Value(nowMs()),
    ));
  }
}

class WorkflowResult {
  final String sessionId;
  final bool cached;
  final String? errorCode;
  final String? errorMessage;
  final String? message;

  const WorkflowResult({
    required this.sessionId,
    required this.cached,
    this.errorCode,
    this.errorMessage,
    this.message,
  });

  bool get ok => errorCode == null;
}
