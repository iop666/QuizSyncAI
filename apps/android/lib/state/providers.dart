import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../services/host_gateway.dart';
import '../services/host_status_poller.dart';
import '../services/live_updates.dart' show taskSignature;
import 'app_state.dart';

/// Android 端状态注入（用户需求 6/7/8/12）。
///
/// main 用真实实例 override；widget 测试用内存库 + 假网关 override，
/// 于是在没有设备也没有模拟器的机器上也能跑完整的界面分支。

/// 全局应用状态（本地库 / 离线队列 / 设置）。
final androidAppProvider = Provider<AndroidAppState>(
  (ref) => throw StateError('androidAppProvider 未注入：请在 ProviderScope 里 override'),
);

/// 配对信息。宿主页（AndroidHomePage）维护，重新配对后同步更新。
final pairingProvider = StateProvider<PairingInfo?>((ref) => null);

/// 主机网关工厂。默认走局域网 HTTP；测试注入假实现。
final hostGatewayFactoryProvider = Provider<HostGateway Function(PairingInfo)>(
  (ref) => (p) => ApiHostGateway(
    ApiClient(baseUrl: p.httpBase, token: p.token),
  ),
);

/// 当前底栏标签（0=当前任务 1=历史记录 2=设置）。
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// 配对探测客户端工厂（配对码换长期 token 的那一次 HTTP）。
///
/// 与 [hostGatewayFactoryProvider] 同样的理由：`flutter_test` 会把所有真实
/// HTTP 请求挡成 400，没有这个缝就覆盖不了「配对成功之后」的分支
/// （切换标签、回到主界面）。生产走真实的 [ApiClient]。
final pairingClientFactoryProvider =
    Provider<ApiClient Function(String baseUrl)>(
  (ref) => (baseUrl) => ApiClient(baseUrl: baseUrl, token: ''),
);

/// 设置变更版本号：`AppSettings` 是 ChangeNotifier 而不是 Riverpod 状态，
/// 宿主监听到变更后 +1，依赖设置的页面 watch 它即可重建。
final settingsRevisionProvider = StateProvider<int>((ref) => 0);

/// 是否建立 WS 长连接（用户需求 7 的自动刷新靠它）。
/// widget 测试把它 override 成 false：测试里不需要真的去连主机。
final liveSyncEnabledProvider = Provider<bool>((ref) => true);

/// 是否开启主机状态轮询兜底（用户反馈 M15 第 4 条）。
///
/// 与 [liveSyncEnabledProvider] 同理，是给 widget 测试留的缝：测试里既没有
/// 真主机、也没必要每秒去连一次，需要覆盖轮询的用例自己把它打开。
final hostPollingEnabledProvider = Provider<bool>((ref) => true);

/// 轮询探测工厂（真机走局域网 HTTP；测试注入不发网络的假实现）。
final hostStatusProbeFactoryProvider =
    Provider<HostStatusProbeFactory>((ref) => defaultHostStatusProbe);

// ============================================================
// 主机状态（需求 6/12：未配对 / 离线 / 未选合集 分别给不同文案）
// ============================================================

enum HostConnection { unpaired, checking, online, offline }

class ServerStatus {
  final HostConnection connection;
  final ServerInfo? info;
  final String? activeCollectionId;
  final String? activeCollectionName;
  final String? errorMessage;

  const ServerStatus({
    this.connection = HostConnection.unpaired,
    this.info,
    this.activeCollectionId,
    this.activeCollectionName,
    this.errorMessage,
  });

  bool get paired => connection != HostConnection.unpaired;

  bool get online => connection == HostConnection.online;

  bool get hasActiveCollection =>
      (activeCollectionId ?? '').isNotEmpty;

  String? get collectionName =>
      (activeCollectionName ?? '').isEmpty ? null : activeCollectionName;

  ServerStatus copyWith({
    HostConnection? connection,
    ServerInfo? info,
    Object? activeCollectionId = _unset,
    Object? activeCollectionName = _unset,
    Object? errorMessage = _unset,
    bool clearInfo = false,
  }) =>
      ServerStatus(
        connection: connection ?? this.connection,
        info: clearInfo ? null : (info ?? this.info),
        activeCollectionId: activeCollectionId == _unset
            ? this.activeCollectionId
            : activeCollectionId as String?,
        activeCollectionName: activeCollectionName == _unset
            ? this.activeCollectionName
            : activeCollectionName as String?,
        errorMessage: errorMessage == _unset
            ? this.errorMessage
            : errorMessage as String?,
      );

  static const _unset = Object();
}

class ServerStatusNotifier extends Notifier<ServerStatus> {
  @override
  ServerStatus build() => const ServerStatus();

  /// 主动探测主机（启动、回到前台、用户点重试时调用）。
  Future<void> refresh([PairingInfo? pairing]) async {
    final info = pairing ?? ref.read(pairingProvider);
    if (info == null) {
      state = const ServerStatus();
      return;
    }
    state = state.copyWith(
        connection: HostConnection.checking, errorMessage: null);
    try {
      final serverInfo = await ref.read(hostGatewayFactoryProvider)(info).info();
      applyInfo(serverInfo);
    } catch (e) {
      state = state.copyWith(
        connection: HostConnection.offline,
        errorMessage: e is ApiClientException ? e.message : '$e',
      );
    }
  }

  /// WS hello 或 HTTP /info 的同一入口。
  void applyInfo(ServerInfo info) {
    state = ServerStatus(
      connection: HostConnection.online,
      info: info,
      activeCollectionId: info.activeCollectionId,
      activeCollectionName: info.activeCollectionName,
    );
  }

  void applyCollection(String? id, String? name) {
    state = state.copyWith(
      connection: state.paired ? HostConnection.online : state.connection,
      activeCollectionId: id,
      activeCollectionName: name,
    );
  }

  void offline(String message) {
    if (!state.paired) return;
    state = state.copyWith(
        connection: HostConnection.offline, errorMessage: message);
  }

  /// 解除配对 / 设备被吊销：回到「未配对」。
  void reset() => state = const ServerStatus();
}

final serverStatusProvider =
    NotifierProvider<ServerStatusNotifier, ServerStatus>(
        ServerStatusNotifier.new);

// ============================================================
// 进行中的识别任务（需求 7：N 张图片识别中…）
// ============================================================

class ActiveTask {
  /// 是否已经发起过一次识别（本机发起或主机发起）。
  final bool started;
  final String? taskId;
  final String? sessionId;
  final TaskState status;
  final int imageCount;
  final String? message;

  /// 上一轮已经完成、**仍留在页面上**的结果（用户需求 3 的「下一轮悬浮窗」）。
  ///
  /// 新识别开始时把上一轮的 sessionId 挪到这里而不是直接清空：页面就在最上方
  /// 加一条悬浮窗显示新一轮进度，下面的旧结果保持可见；新一轮出结果时才换掉。
  final String? shownSessionId;

  /// 主机任务已完成、但「当前任务」页还没自动进入结果页。
  /// 页面消费一次（[ActiveTaskNotifier.consumeAutoOpen]）后清掉，保证只跳一次。
  final bool autoOpenResult;

  /// 这一轮是不是**主机（Windows）自己发起**的识别（用户反馈 M16 第 3 条）。
  ///
  /// 用来决定「结果页上方那条悬浮窗要不要出现」：电脑在自己截屏识别时，
  /// 手机即使已经停在某次结果页上也要看得见进度（并在完成后跳过去）；
  /// 而本机（悬浮球 / 相册）识别一律静默（用户需求 3），不能因为主机把
  /// 同一条任务也广播回来就当成「电脑在识别」。
  final bool hostInitiated;

  const ActiveTask({
    this.started = false,
    this.taskId,
    this.sessionId,
    this.status = TaskState.queued,
    this.imageCount = 0,
    this.message,
    this.shownSessionId,
    this.autoOpenResult = false,
    this.hostInitiated = false,
  });

  bool get idle => !started;

  bool get running =>
      started && (status == TaskState.queued || status == TaskState.analyzing);

  bool get failed => started && status == TaskState.failed;

  bool get finished => started && status == TaskState.done;

  /// 正在识别、同时页面上还留着上一轮的结果 → 上方显示悬浮窗（用户需求 3）。
  bool get showsPreviousResult =>
      running && (shownSessionId ?? '').isNotEmpty;

  /// 新一轮完成：悬浮窗短暂显示「识别完成」，随后自动进入结果页（用户需求 3）。
  bool get completesIntoBanner =>
      finished && autoOpenResult && (shownSessionId ?? '').isNotEmpty;

  ActiveTask copyWith({bool? autoOpenResult}) => ActiveTask(
        started: started,
        taskId: taskId,
        sessionId: sessionId,
        status: status,
        imageCount: imageCount,
        message: message,
        shownSessionId: shownSessionId,
        autoOpenResult: autoOpenResult ?? this.autoOpenResult,
        hostInitiated: hostInitiated,
      );
}

class ActiveTaskNotifier extends Notifier<ActiveTask> {
  @override
  ActiveTask build() => const ActiveTask();

  /// 上一轮已显示的结果 → [ActiveTask.shownSessionId]（没完成就沿用原值）。
  static String? _carryOver(ActiveTask state) => state.status == TaskState.done
      ? (state.sessionId ?? state.shownSessionId)
      : state.shownSessionId;

  /// 本机（悬浮球 / 相册）或主机开始一次新识别。
  ///
  /// [hostInitiated] 只在「本机请求主机重新生成」时为 true（那确实是在等电脑
  /// 干活）；悬浮球 / 相册上传都是本机识别，默认 false。
  void begin({
    String? taskId,
    String? sessionId,
    int imageCount = 1,
    bool hostInitiated = false,
  }) {
    state = ActiveTask(
      started: true,
      taskId: taskId,
      sessionId: sessionId,
      status: TaskState.analyzing,
      imageCount: imageCount < 1 ? 1 : imageCount,
      shownSessionId: _carryOver(state),
      hostInitiated: hostInitiated,
    );
  }

  /// 主机的 `task_update`。
  void update({
    String? taskId,
    required TaskState status,
    String? sessionId,
    int imageCount = 0,
  }) {
    final incomingId = (taskId ?? '').isEmpty ? null : taskId;
    final incomingSession = (sessionId ?? '').isEmpty ? null : sessionId;
    final running =
        status == TaskState.queued || status == TaskState.analyzing;
    // 同一轮任务的多次上报（queued → analyzing）不是新一轮，不能把旧结果再挪一次。
    final sameRound = state.running &&
        (incomingId == null ||
            state.taskId == null ||
            incomingId == state.taskId);
    state = ActiveTask(
      started: true,
      taskId: incomingId ?? state.taskId,
      sessionId: incomingSession ?? state.sessionId,
      status: status,
      imageCount: imageCount > 0 ? imageCount : state.imageCount,
      shownSessionId:
          running && !sameRound ? _carryOver(state) : state.shownSessionId,
      autoOpenResult: sameRound && state.autoOpenResult,
      // 本机发起的任务，主机会把同一条状态**广播回来**：同一轮里必须保留
      // 「这是本机识别」（否则手机自己的识别会被当成「电脑在识别」而跳页）。
      hostInitiated: sameRound ? state.hostInitiated : true,
    );
  }

  void failed(String? message) {
    state = ActiveTask(
      started: true,
      taskId: state.taskId,
      sessionId: state.sessionId,
      status: TaskState.failed,
      imageCount: state.imageCount,
      message: message,
      shownSessionId: state.shownSessionId,
      hostInitiated: state.hostInitiated,
    );
  }

  /// 完成。`autoOpen: true` 表示这是**主机**发起的识别（用户需求 3）：
  /// 页面会自动进入本次结果页；本机识别（默认）保持静默，只更新当前任务页。
  void done({String? sessionId, bool autoOpen = false}) {
    state = ActiveTask(
      started: true,
      taskId: state.taskId,
      sessionId: sessionId ?? state.sessionId,
      status: TaskState.done,
      imageCount: state.imageCount,
      shownSessionId: state.shownSessionId,
      autoOpenResult: autoOpen,
      hostInitiated: state.hostInitiated,
    );
  }

  /// 页面已经自动进入结果页（或结果页不存在）：清掉待跳标记，只跳一次。
  void consumeAutoOpen() {
    if (!state.autoOpenResult) return;
    state = state.copyWith(autoOpenResult: false);
  }

  void clear() => state = const ActiveTask();
}

/// 界面当前展示的任务签名（M17 第 4 条）：与主机侧同一拼法（见 [taskSignature]）。
///
/// 轮询器拿它和主机上报的签名对比：**界面停在别的任务上**就补发一次通知，
/// 否则「通知丢过一次」之后页面会永远停在旧内容上（用户第二次反馈
/// 「windows 识别时安卓端当前任务又不直接刷新」）。
String activeTaskSignature(ActiveTask task) => task.started
    ? taskSignature(task.status, task.sessionId, task.imageCount)
    : '';

final activeTaskProvider =
    NotifierProvider<ActiveTaskNotifier, ActiveTask>(ActiveTaskNotifier.new);

/// 结果页上方那条「电脑正在识别中」悬浮窗要不要出现（用户反馈 M16 第 3 条）。
///
/// 用户原话：**「安卓端已经进入识别结果后，Windows 端识别时安卓端不显示」**。
/// 抽屉里的「当前任务」页本来就有这条悬浮窗，但它是被压在结果页**下面**的
/// （`IndexedStack`），用户停在结果页上时什么都看不到。所以结果页自己也要显示
/// ——条件与「当前任务」页一致：机器发起的识别、而且不是**页面上这次**结果
/// （正在看的那次自己的「重新生成」不算新的一轮，它有顶栏的转圈）。
bool showsHostProgress(ActiveTask task, String currentSessionId) {
  if (!task.running || !task.hostInitiated) return false;
  final sid = task.sessionId;
  return sid == null || sid.isEmpty || sid != currentSessionId;
}

/// 新一轮刚出结果、马上要跳到它（用户反馈 M16 第 3 条）：先显示「识别完成」。
///
/// 真正 push 新结果页的是「当前任务」页（它一直挂在 `IndexedStack` 里、
/// `autoOpenResult` 一跳一次 —— 单一出口，不会两个页面各推一个），这里只负责
/// 让用户**在结果页上也看得见**「完成了，正在打开」。
bool showsHostDone(ActiveTask task, String currentSessionId) {
  if (!task.finished || !task.autoOpenResult || !task.hostInitiated) {
    return false;
  }
  final sid = task.sessionId;
  return sid != null && sid.isNotEmpty && sid != currentSessionId;
}

// ============================================================
// 本地数据（WS 事件统一 invalidate 这几个 provider）
// ============================================================

/// 会话列表；[collectionId] 为空 = 全部（含未分类）。
final sessionsProvider =
    FutureProvider.family<List<Session>, String?>((ref, collectionId) async {
  final app = ref.watch(androidAppProvider);
  return app.repo.listSessions(collectionId: collectionId);
});

final sessionQuestionsProvider =
    FutureProvider.family<List<Question>, String>((ref, sessionId) async {
  final app = ref.watch(androidAppProvider);
  return app.repo.questionsOfSession(sessionId);
});

final sessionImagesProvider =
    FutureProvider.family<List<String>, String>((ref, sessionId) async {
  final app = ref.watch(androidAppProvider);
  return app.repo.imageHashesOf(sessionId);
});

final sessionProvider =
    FutureProvider.family<Session?, String>((ref, sessionId) async {
  final app = ref.watch(androidAppProvider);
  return app.repo.getSession(sessionId);
});

final collectionsProvider = FutureProvider<List<Collection>>((ref) async {
  final app = ref.watch(androidAppProvider);
  return app.repo.listCollections();
});

/// 某个历史分组下的识别记录（[collectionId] 为 null = 「未分类」）。
/// repo 的 `collectionId: null` 表示「全部」，所以未分类只能在这里筛。
Future<List<Session>> sessionsOfGroup(
    CoreRepository repo, String? collectionId) async {
  if (collectionId != null && collectionId.isNotEmpty) {
    return repo.listSessions(collectionId: collectionId);
  }
  final collections = await repo.listCollections();
  final known = collections.map((c) => c.collectionId).toSet();
  final all = await repo.listSessions(limit: 2000);
  return all
      .where((s) =>
          s.collectionId == null ||
          s.collectionId!.isEmpty ||
          !known.contains(s.collectionId))
      .toList();
}

/// 未归属合集（或所属合集已被删除）的历史记录。
final unclassifiedSessionsProvider = FutureProvider<List<Session>>((ref) async {
  final app = ref.watch(androidAppProvider);
  return sessionsOfGroup(app.repo, null);
});

/// 历史记录的一个分组：某个合集，或「未分类」。
class CollectionGroup {
  final String? collectionId;
  final String title;
  final int count;

  const CollectionGroup({
    required this.collectionId,
    required this.title,
    required this.count,
  });

  bool get isUnclassified => collectionId == null;
}

/// 历史 tab 顶层的合集分组（用户需求 8）。
final collectionGroupsProvider =
    FutureProvider<List<CollectionGroup>>((ref) async {
  final app = ref.watch(androidAppProvider);
  final collections = await app.repo.listCollections();
  final sessions = await app.repo.listSessions(limit: 2000);
  final known = collections.map((c) => c.collectionId).toSet();
  final counts = <String?, int>{};
  for (final s in sessions) {
    final id = s.collectionId;
    final key = (id == null || id.isEmpty || !known.contains(id)) ? null : id;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return [
    for (final c in collections)
      CollectionGroup(
        collectionId: c.collectionId,
        title: c.name,
        count: counts[c.collectionId] ?? 0,
      ),
    if ((counts[null] ?? 0) > 0)
      CollectionGroup(
        collectionId: null,
        title: '未分类',
        count: counts[null] ?? 0,
      ),
  ];
});
