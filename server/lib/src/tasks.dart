import 'dart:async';
import 'dart:typed_data';

import '../quizsync_server_core.dart';
import 'constants.dart';
import 'engine.dart';
import 'store.dart';
import 'terminal.dart';

/// 一页待识别的图片。
class PageInput {
  final String hash;
  final Uint8List jpeg;
  final int width;
  final int height;

  const PageInput({
    required this.hash,
    required this.jpeg,
    required this.width,
    required this.height,
  });
}

/// 一次识别任务的结局。
class TaskOutcome {
  final String taskId;
  final String sessionId;
  final bool ok;
  final String? errorCode;
  final String? errorMessage;
  final int questionCount;
  final int latencyMs;

  const TaskOutcome({
    required this.taskId,
    required this.sessionId,
    required this.ok,
    this.errorCode,
    this.errorMessage,
    this.questionCount = 0,
    this.latencyMs = 0,
  });
}

/// 识别流水线：**截图（或手机上传）的图片 → 会话 → AI → 结果落库 → 广播**。
///
/// 这是 Server 唯一的一条业务链路，本机热键与手机的 `POST /api/v1/tasks`
/// 共用它（Desktop 版对应 `AnalysisWorkflow` + `ServerTaskExecutor` 两套，
/// Server 功能冻结、没有任务队列，也不需要区分来源，所以合成一个）。
class ServerTasks {
  final ServerStore store;
  final RecognitionEngine engine;
  final Terminal log;

  /// 实时读 AI 配置（改完 API Key 不必重启）。
  final AiConfig Function() configProvider;

  /// 状态广播出口（服务端转发成 WS `task_update` / `task_result` / `task_failed`）。
  final void Function(
    String taskId,
    String status,
    String? sessionId,
    int imageCount,
  ) onUpdate;

  bool _busy = false;

  /// 是否有识别在跑（CLI 用它拒绝并发热键，避免两张图抢同一个 AI 配额）。
  bool get busy => _busy;

  ServerTasks({
    required this.store,
    required this.engine,
    required this.configProvider,
    required this.onUpdate,
    required this.log,
  });

  /// 跑一次识别。返回结局（调用方负责日志）。
  ///
  /// [collectionId] 为空时用 Server 的默认合集（协议要求会话必须属于某个合集）。
  ///
  /// 同一时刻只允许一条链路（Server 是个人后台服务，一次只处理一次识别；
  /// 并发跑只会两张图抢同一份 AI 配额，也容易让手机端的「识别中」状态错乱）。
  Future<TaskOutcome> run({
    required List<PageInput> pages,
    required String sourceDevice,
    String? collectionId,
    String? taskId,
    String? sessionId,
  }) async {
    if (_busy) {
      return TaskOutcome(
        taskId: taskId ?? '',
        sessionId: sessionId ?? '',
        ok: false,
        errorCode: 'busy',
        errorMessage: '已有识别正在进行，请等它结束',
      );
    }
    _busy = true;
    try {
      return await _runInner(
        pages: pages,
        sourceDevice: sourceDevice,
        collectionId: collectionId,
        taskId: taskId,
        sessionId: sessionId,
      );
    } finally {
      _busy = false;
    }
  }

  Future<TaskOutcome> _runInner({
    required List<PageInput> pages,
    required String sourceDevice,
    String? collectionId,
    String? taskId,
    String? sessionId,
  }) async {
    if (pages.isEmpty) {
      return TaskOutcome(
        taskId: taskId ?? '',
        sessionId: sessionId ?? '',
        ok: false,
        errorCode: 'internal',
        errorMessage: '没有可分析的图片',
      );
    }
    if (pages.length > kHardMaxPagesPerTask) {
      return TaskOutcome(
        taskId: taskId ?? '',
        sessionId: sessionId ?? '',
        ok: false,
        errorCode: 'too_many_pages',
        errorMessage: '一次最多 $kHardMaxPagesPerTask 页（当前 ${pages.length} 页）',
      );
    }

    final now = nowMs();
    final tid = taskId ?? newUuidV4();
    final sid = sessionId ?? newUuidV4();

    // 1. 图片落盘（截图路径在这里写；手机上传的图早就写过了，幂等跳过）。
    //    页序用**落盘返回的** hash：hash 永远是对字节算出来的，调用方传进来的
    //    值只作参考，这样「图片元数据」与「磁盘文件」不可能对不上。
    final hashes = <String>[];
    for (final page in pages) {
      final meta =
          await store.writeImage(page.jpeg, width: page.width, height: page.height);
      hashes.add(meta.hash);
    }

    // 2. 会话 + 页序。
    final reused = store.getSession(sid);
    var session = Session(
      sessionId: sid,
      taskId: tid,
      collectionId: collectionId ?? store.collection.collectionId,
      imageHash: hashes.first,
      sourceDevice: sourceDevice,
      status: TaskState.analyzing,
      createdAt: reused?.session.createdAt ?? now,
      updatedAt: now,
      updatedBy: store.deviceId,
    );
    await store.putSession(StoredSession(
      session: session,
      questions: const [],
      imageHashes: hashes,
    ));
    onUpdate(tid, 'analyzing', sid, hashes.length);

    final config = configProvider();
    if (!config.configured) {
      session = session.copyWith(
        status: TaskState.failed,
        errorCode: 'ai_auth',
        errorMessage: '主机尚未配置 AI',
        updatedAt: nowMs(),
      );
      await store.putSession(StoredSession(
        session: session,
        questions: const [],
        imageHashes: hashes,
      ));
      onUpdate(tid, 'failed', sid, hashes.length);
      return TaskOutcome(
        taskId: tid,
        sessionId: sid,
        ok: false,
        errorCode: 'ai_auth',
        errorMessage: '主机尚未配置 AI',
      );
    }

    // 3. AI。
    final outcome = await engine.recognize(
      jpegBytesList: pages.map((p) => p.jpeg).toList(),
      config: config,
    );

    // 4. 落库 + 广播。
    final questions = outcome.questions
        .map((q) => q.copyWith(sessionId: sid))
        .toList();
    session = session.copyWith(
      status: outcome.ok ? TaskState.done : TaskState.failed,
      errorCode: outcome.errorCode,
      errorMessage: outcome.errorMessage,
      aiProvider: config.providerId,
      aiModel: config.model,
      promptVersion: computePromptVersion(),
      rawResponse: outcome.rawText.isEmpty ? null : outcome.rawText,
      questionCount: questions.length,
      latencyMs: outcome.latencyMs,
      updatedAt: nowMs(),
    );
    await store.putSession(StoredSession(
      session: session,
      questions: questions,
      imageHashes: hashes,
    ));
    onUpdate(tid, outcome.ok ? 'done' : 'failed', sid, hashes.length);

    return TaskOutcome(
      taskId: tid,
      sessionId: sid,
      ok: outcome.ok,
      errorCode: outcome.errorCode,
      errorMessage: outcome.errorMessage,
      questionCount: questions.length,
      latencyMs: outcome.latencyMs,
    );
  }

  /// 「重新生成」（安卓结果页的按钮）：按既有会话的页序起一个**新会话**再跑一次。
  ///
  /// 返回新会话 id（调用方立刻用它回 202；识别在后台跑，进度照常走 task_update）。
  Future<String?> startReanalyze(String sessionId, String sourceDevice) async {
    final existing = store.getSession(sessionId);
    if (existing == null) return null;
    final pages = await _pagesOf(existing.imageHashes);
    if (pages == null) return null;
    final newSessionId = newUuidV4();
    unawaited(run(
      pages: pages,
      sourceDevice: sourceDevice,
      collectionId: existing.session.collectionId,
      sessionId: newSessionId,
    ));
    return newSessionId;
  }

  /// 失败任务的重试：**复用同一个会话与 task_id**（protocol.md：重试不改 id，
  /// 手机端还挂在原来那个任务上）。
  Future<void> retrySession(String sessionId) async {
    final existing = store.getSession(sessionId);
    if (existing == null) return;
    final pages = await _pagesOf(existing.imageHashes);
    if (pages == null) return;
    unawaited(run(
      pages: pages,
      sourceDevice: existing.session.sourceDevice,
      collectionId: existing.session.collectionId,
      taskId: existing.session.taskId,
      sessionId: sessionId,
    ));
  }

  /// 同图去重（protocol.md 3.3：同页序 + 已 done → 直接复用，不再花一次 AI）。
  ///
  /// 多页必须**页序完全一致**才算命中，否则「首页相同、后续页不同」会被错误
  /// 复用成另一组题目的结果。
  StoredSession? findReusable(List<String> hashes) {
    if (hashes.isEmpty) return null;
    for (final stored in store.sessions.values) {
      if (stored.session.status != TaskState.done) continue;
      if (stored.session.isDeleted) continue;
      if (stored.imageHashes.length != hashes.length) continue;
      var same = true;
      for (var i = 0; i < hashes.length; i++) {
        if (stored.imageHashes[i] != hashes[i]) {
          same = false;
          break;
        }
      }
      if (same) return stored;
    }
    return null;
  }

  Future<List<PageInput>?> _pagesOf(List<String> hashes) async {
    final pages = <PageInput>[];
    for (final hash in hashes) {
      final bytes = await store.readImage(hash);
      if (bytes == null) return null;
      pages.add(PageInput(hash: hash, jpeg: bytes, width: 0, height: 0));
    }
    return pages.isEmpty ? null : pages;
  }
}
