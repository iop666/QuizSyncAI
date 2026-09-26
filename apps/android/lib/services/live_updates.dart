import 'package:quizsync_core/quizsync_core.dart';

import '../state/app_state.dart';
import 'host_gateway.dart';

/// WS 事件落地 + 通知宿主刷新（用户需求 7）。
///
/// 纯逻辑、无平台依赖：单测可以直接喂一条 `task_result` 消息，断言
/// 「本地库出现这条记录 + 宿主被通知失效缓存」。
/// 主 agent 要求「不要只靠手动下拉」——所有自动刷新都从这里发出去。
abstract class LiveUpdateSink {
  /// hello / collection_changed：主机当前合集变化。
  void collectionChanged(String? collectionId, String? collectionName);

  /// 主机在线且报出了自己的信息。
  void serverInfo(ServerInfo info);

  /// 任务状态变化：`analyzing` / `queued` / `done` / `failed`。
  void taskUpdate({
    required String taskId,
    required TaskState status,
    String? sessionId,
    int imageCount,
  });

  /// 结果落库（会自动刷新历史列表与结果页）。
  ///
  /// [selfInitiated] = 这条结果对应的是**本机自己发起**的识别（相册选图 /
  /// 悬浮球）。本机识别全程静默（用户需求 3），结果只更新「当前任务」页，
  /// 绝不能因为主机也广播了一次 task_result 就自动跳出结果页。
  void taskResult({
    required String sessionId,
    required int questionCount,
    bool selfInitiated,
  });

  void taskFailed({required String taskId, String? message});

  /// 断连：UI 需要把「在线」改成「电脑未连接」。
  void offline(String message);

  /// 主机的 sync ops / 设备吊销等：只需让本地数据重新读一遍。
  void dataChanged();

  /// token 失效 / 设备被吊销：必须重新配对。
  void deviceRevoked();
}

/// 把 WS 消息翻译成「本地库写入 + 宿主通知」。
class LiveUpdates {
  LiveUpdates({required this.app, required this.sink});

  final AndroidAppState app;
  final LiveUpdateSink sink;

  /// 处理一条 WS 消息；未知类型忽略（协议向前兼容）。
  Future<void> handle(Map<String, dynamic> msg) async {
    switch (msg['type']) {
      case 'hello':
        applyHello(msg);
        break;
      case 'collection_changed':
        sink.collectionChanged(
          msg['collection_id']?.toString(),
          msg['collection_name']?.toString(),
        );
        break;
      case 'task_update':
        await _taskUpdate(msg);
        break;
      case 'task_result':
        await _taskResult(msg);
        break;
      case 'task_failed':
        sink.taskFailed(
          taskId: msg['task_id']?.toString() ?? '',
          message: msg['message']?.toString(),
        );
        break;
      case 'ops':
        sink.dataChanged();
        break;
      case 'device_revoked':
      case 'auth_failed':
        // 通知必须发出去：即使清理本地配对信息失败，界面也要回到「未配对」，
        // 否则用户会停在一个永远连不上的「已配对」状态里。
        try {
          await app.clearPairing();
        } finally {
          sink.deviceRevoked();
        }
        break;
      default:
        break;
    }
  }

  /// 主机 hello：带上当前合集（用户需求 12），安卓据此判断能否发起识别。
  void applyHello(Map<String, dynamic> msg) {
    if (msg.containsKey('active_collection_id') ||
        msg.containsKey('active_collection_name')) {
      sink.collectionChanged(
        msg['active_collection_id']?.toString(),
        msg['active_collection_name']?.toString(),
      );
    }
    sink.serverInfo(ServerInfo(
      deviceId: msg['server_device_id']?.toString() ?? '',
      deviceName: '',
      platform: 'windows',
      protocolVersion: (msg['protocol_version'] as num?)?.toInt() ?? 0,
      appVersion: '',
      aiConfigured: true,
      capabilities: const [],
      activeCollectionId: msg['active_collection_id']?.toString(),
      activeCollectionName: msg['active_collection_name']?.toString(),
    ));
  }

  /// `task_update`：主机（含 Windows 本地截屏）广播的任务状态。
  ///
  /// 页数**优先用消息里的 `image_count`**（用户需求 2）：主机本地截屏起的任务，
  /// 手机本地库里还没有这条会话，查库只会得到 0，界面就会一直显示
  /// 「1 张图片识别中…」。只有主机没带页数时才退回本地库查。
  Future<void> _taskUpdate(Map<String, dynamic> msg) async {
    final sessionId = msg['session_id']?.toString();
    final status = TaskState.parse(msg['status']?.toString());
    var imageCount = _asInt(msg['image_count']);
    if (imageCount <= 0 && sessionId != null && sessionId.isNotEmpty) {
      imageCount = (await app.repo.imageHashesOf(sessionId)).length;
    }
    // session_id 在本地库里还不存在也要照常上报：界面靠这条状态显示
    // 「N 张图片识别中…」，结果到达时再由 task_result 落库。
    sink.taskUpdate(
      taskId: msg['task_id']?.toString() ?? '',
      status: status,
      sessionId: sessionId,
      imageCount: imageCount,
    );
  }

  /// 协议字段是数字，但容忍字符串形式（老版本 / 手工构造的消息）。
  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// task_result 带完整会话与题目：落本地库后由宿主 invalidate provider，
  /// 历史列表与结果页就会自动刷新（用户不再需要手动下拉）。
  ///
  /// M47：题目落库改走 `applyAnalysisResult`（`data-model.md` 2.3 的落库入口），
  /// 不再逐个 `upsertQuestion` —— 主机重分析一条**手机端改过答案**的记录时，
  /// 前者会保住 `answer_edited` / `analysis_edited` 的字段，后者会把用户的手改
  /// 直接盖掉（而且本机随后还会把被盖掉的值当成本地改动同步回主机）。
  /// 顺带把「本轮已经不存在的题目」按同一入口软删除，两端题目集合保持一致。
  Future<void> _taskResult(Map<String, dynamic> msg) async {
    final raw = msg['session'];
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final session = Session.fromJson(map);
    await app.repo.upsertSession(session);

    final questions = <Question>[];
    final rawQuestions = map['questions'];
    if (rawQuestions is List) {
      for (final q in rawQuestions) {
        if (q is! Map) continue;
        questions.add(Question.fromJson(Map<String, dynamic>.from(q)));
      }
    }
    await app.repo.applyAnalysisResult(
      sessionId: session.sessionId,
      input: AnalysisResultInput(
        aiProvider: session.aiProvider,
        aiModel: session.aiModel,
        promptVersion: session.promptVersion,
        rawResponse: session.rawResponse,
        latencyMs: session.latencyMs,
        cached: session.cached,
        questions: [
          for (final q in questions) q.copyWith(sessionId: session.sessionId),
        ],
      ),
    );

    // 多页页序（用户需求 4）：结果里的 image_hashes 是权威顺序。
    final rawHashes = map['image_hashes'];
    if (rawHashes is List && rawHashes.isNotEmpty) {
      await app.repo.setSessionImages(
        session.sessionId,
        rawHashes.map((e) => e.toString()).toList(),
      );
    }

    sink.taskResult(
      sessionId: session.sessionId,
      questionCount: questions.isEmpty
          ? session.questionCount
          : questions.length,
      // 主机把**手机自己提交**的任务也广播回来了：靠 source_device 认出来，
      // 否则本机识别也会自动跳结果页（违反用户需求 3 的「静默识别」）。
      selfInitiated: session.sourceDevice == app.repo.deviceId,
    );
  }
}

/// 主机未选合集时的统一处理（用户需求 12）：409 与本地判断走同一句文案。
bool isNoActiveCollection(Object error) =>
    error is ApiClientException && error.code == 'no_active_collection';

/// 任务签名的**唯一**拼法（M17 第 4 条）：`状态|会话 id`（进行中再带页数）。
///
/// 主机侧（`HostStatusPoller.signatureOf`）与界面侧（`activeTaskSignature`）
/// 都用它，于是「主机说的」和「界面显示的」可以直接比字符串 —— 对不上就补发
/// 一次通知，解决「当前任务页停在旧内容上」。
///
/// 终态**不带页数**：页数只是「N 张图片识别中」的展示细节，两边不一致时若判成
/// 「另一个任务」，会把同一条 `task_result` 再通知一次，而它带 `autoOpenResult`
/// —— 结果是**重复跳一次结果页**。
String taskSignature(TaskState status, String? sessionId, int imageCount) {
  final running = status == TaskState.queued || status == TaskState.analyzing;
  if (!running && status != TaskState.done && status != TaskState.failed) {
    return '';
  }
  final base = '${status.wire}|${sessionId ?? ''}';
  return running ? '$base|${imageCount < 1 ? 1 : imageCount}' : base;
}

/// 把任意异常转成给用户看的一句话。
String hostErrorMessage(Object error) {
  if (isNoActiveCollection(error)) return kNoActiveCollectionMessage;
  if (error is ApiClientException) return error.message;
  return '$error';
}
