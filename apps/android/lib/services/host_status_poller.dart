import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../state/app_state.dart';
import 'live_updates.dart';

/// 轮询间隔（用户反馈 M15 第 4 条原话：「又没有方法让他一直刷新，比如安卓端
/// 1s 获取一次状态」）。做成常量而不是散落的字面量，是为了让测试能按同一个
/// 节奏驱动，不必等真的 1 秒。
const Duration kHostStatusPollInterval = Duration(milliseconds: 1000);

/// 一次探测：问主机「你现在在识别什么」。
typedef HostStatusProbe = Future<ActiveTaskView> Function();

/// 造探测函数（每个配对一份，内部持有 [ApiClient]）。
typedef HostStatusProbeFactory = HostStatusProbe Function(PairingInfo pairing);

/// 默认实现：局域网 HTTP（与上传、拉取 op 是同一台主机、同一个 token）。
HostStatusProbe defaultHostStatusProbe(PairingInfo pairing) {
  final api = ApiClient(baseUrl: pairing.httpBase, token: pairing.token);
  return api.fetchActiveTask;
}

/// 主机状态轮询兜底（用户反馈 M15 第 4 条）。
///
/// 为什么还要它：M14 已经做了「WS 断线重连后补齐 + 握手时补发进行中的本机
/// 任务」，但用户那边**仍然**看不到刷新。最可能的原因是那台机器上 WS 推送
/// 根本连不上 / 不稳定（而 HTTP 一直是好的 —— 手机→Windows 的上传是通的）。
/// 所以除了推送，再加一条「问一句」的兜底：就算一条推送都没收到，界面也会
/// 自己跟上。
///
/// 四条约束（来自需求，逐条对应下面的实现）：
/// 1. **只问状态**，绝不在这里跑 `AndroidSync.runFull`（那会 drain 离线队列并
///    push ops，一秒一次既太重又会重复上传）；
/// 2. 与 WS **完全相同的语义**：把结果拼成同样的消息交给 [LiveUpdates]，
///    于是「识别中显示 N 张 / 出结果自动进结果页 / 本机自己发起的识别保持
///    静默」三条行为天然一致，没有第二套 UI 逻辑；
/// 3. 状态没变就**一条通知都不发**（每秒 invalidate 整个列表会抖）；
/// 4. 失败静默降级：最多把状态行改成「电脑未连接」，绝不弹 SnackBar。
///
/// 生命周期由宿主（`AndroidHomePage`）管：配对成功且 App 在前台时 [start]，
/// dispose / 取消配对 / 进后台时 [stop]。本类自己也可以被单测直接驱动。
class HostStatusPoller {
  HostStatusPoller({
    required this.updates,
    required this.probeFactory,
    this.interval = kHostStatusPollInterval,
    this.uiSignature,
    this.onRemoteOps,
    this.onHostCollections,
  });

  /// WS 那套落地逻辑（本地库写入 + 宿主通知），轮询复用同一份。
  final LiveUpdates updates;

  final HostStatusProbeFactory probeFactory;
  final Duration interval;

  /// **界面当前展示的任务签名**（`RefLiveUpdateSink` 注入，格式见
  /// [HostStatusPoller.signatureOf]）。
  ///
  /// 为什么轮询器自己记的指纹还不够（M17 第 4 条）：它只说明**它通知过什么**，
  /// 不说明**界面现在显示什么** —— 用户点过「忽略 / 知道了」把状态清空、或者
  /// 某次通知落在了正被结果页盖住的页面上，指纹相同就再也不会补发，用户看到
  /// 的就是「当前任务还是不刷新」。所以只要主机说的与界面显示的不一致，就再
  /// 通知一次（下发是幂等的）。
  final String Function()? uiSignature;

  /// 主机**本地 ops 水位**涨了 → 宿主做一次「只拉不推」的同步
  /// （M17 第 5 条：Windows 上改题目等改动，手机前台 1 秒内跟上）。
  final void Function()? onRemoteOps;

  /// 主机上报的**当前活跃合集列表**（M18 第 4 条）。
  ///
  /// 用户原话：「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」。
  /// 合集在手机本地那一行原来只能靠 ops 拉取落地，而拉取是被 `opsLamport`
  /// 水位这种**间接信号**触发的（基线错一次就永久漏）。这里直接把「主机现在有
  /// 哪些合集」这份**想要的结果**交给宿主去对齐本地库，差什么补什么、且与水位
  /// 无关 —— 只要轮询在跑（用户要求「只要在前台就一秒一刷新」），就不会漏。
  ///
  /// 只在列表**指纹变化**时（含第一次观测）调用一次，宿主侧落地是幂等的。
  /// 返回的 Future 会被等：写库失败时本轮不算数，下一轮探测会重试。
  final Future<void> Function(List<Collection> collections)? onHostCollections;

  Timer? _timer;
  HostStatusProbe? _probe;

  /// 第几「代」。`stop()` 会让正在飞的那次探测作废：App 回前台重启后，
  /// 上一代迟到的响应不能当成本轮的状态变化。
  int _generation = 0;

  /// 正在飞的那次探测属于哪一代；null = 空闲。用代次而不是 bool，是因为
  /// 被作废的那次请求回来时**不能**清掉新一轮的标记（否则会误判成空闲，
  /// 于是一秒钟内连发两次请求）。
  int? _inFlight;

  /// 上一次看到的状态（null = 还没建立基线）。
  _TaskFingerprint? _last;

  /// 上一次看到的合集：只有变了才通知，避免每秒重建状态行。
  _CollectionFingerprint? _collection;

  /// 已经推过结果的会话（同一个会话只让页面跳一次结果页）。
  String? _deliveredResult;

  /// 上一次探测是否成功；false 时界面显示「电脑未连接」。
  bool _online = true;

  /// 当前配对的标识。App 切后台再回前台会 stop → start，**同一次配对必须
  /// 保留基线**：否则「后台期间主机出结果」会被当成第一次观测而丢掉，
  /// 回到前台后页面永远停在「识别中」。
  String? _pairingKey;

  /// 上一次看到的主机 ops 水位（null = 还没建立基线；第一次只记基线，
  /// 不然每次开 App 都要白拉一次 ops）。
  int? _opsWatermark;

  /// 上一次看到的主机合集列表指纹（M18 第 4 条；null = 还没镜像过）。
  String? _hostCollections;

  bool get running => _timer != null;

  @visibleForTesting
  bool get online => _online;

  /// 开始轮询（同一次配对重复调用是安全的：只重启定时器，基线保留）。
  void start(PairingInfo pairing) {
    final key = '${pairing.host}:${pairing.port}:${pairing.token}';
    final sameHost = key == _pairingKey;
    stop();
    _pairingKey = key;
    if (!sameHost) {
      // 换了主机 / 重新配对：旧基线一概作废（第一轮只建立基线，不通知）。
      _last = null;
      _collection = null;
      _deliveredResult = null;
      _opsWatermark = null;
      _hostCollections = null;
      _online = true;
    }
    _probe = probeFactory(pairing);
    _timer = Timer.periodic(interval, (_) => unawaited(pollOnce()));
    // 立刻问一次：用户按下热键随手打开 App 时不必再等满一个间隔。
    unawaited(pollOnce());
  }

  void stop() {
    _generation++;
    _inFlight = null;
    _timer?.cancel();
    _timer = null;
    _probe = null;
  }

  /// 问一次并落地。定时器每秒调它，测试也可以直接调（不必等真实时间）。
  @visibleForTesting
  Future<void> pollOnce() async {
    // 上一次还没回来就跳过这一轮：连接超时是 5s、间隔是 1s，不挡住的话
    // 一台不可达的主机会被叠加出好几个并发请求。
    if (_inFlight != null) return;
    final probe = _probe;
    if (probe == null) return;
    final generation = _generation;
    _inFlight = generation;
    try {
      final view = await probe();
      if (generation != _generation) return; // 已被 stop()：这一代的结果作废
      await _apply(view);
    } catch (error) {
      if (generation != _generation) return;
      _applyFailure(error);
    } finally {
      if (_inFlight == generation) _inFlight = null;
    }
  }

  // ------------------------------------------------------------
  // 把探测结果翻译成与 WS 完全相同的消息
  // ------------------------------------------------------------

  Future<void> _apply(ActiveTaskView view) async {
    final wasOffline = !_online;
    _online = true;

    // 主机本地改动的水位（M17 第 5 条）：涨了就通知宿主「只拉一次 ops」。
    // 第一次只建立基线；水位不涨时一个字节都不多发。
    if (view.opsLamport > 0) {
      final last = _opsWatermark;
      _opsWatermark = view.opsLamport;
      if (last != null && view.opsLamport > last) {
        try {
          onRemoteOps?.call();
        } catch (_) {
          // 拉取失败由宿主自己下次再试，不能影响状态轮询。
        }
      }
    }

    // 主机当前有哪些合集（M18 第 4 条）：把这份「想要的结果」交给宿主打进本地库。
    // 第一次观测就要镜像（这一步不依赖任何水位基线，所以「基线错一次就永久漏」
    // 的老毛病不存在了）；之后只在指纹变化时再叫一次。
    final hostCollections = view.collections;
    if (hostCollections.isNotEmpty) {
      final collectionsFingerprint = hostCollections
          .map((c) => '${c.collectionId}:${c.name}:${c.updatedAt}')
          .join('|');
      if (collectionsFingerprint != _hostCollections) {
        _hostCollections = collectionsFingerprint;
        try {
          await onHostCollections?.call(hostCollections);
        } catch (_) {
          // 镜像失败（库暂时不可写等）：把指纹撤回去，下一轮探测会重试
          // （合集列表是幂等的，重复镜像不会写脏数据）。
          _hostCollections = null;
        }
      }
    }

    // 合集走 `collection_changed` 那条老路（不是新加一套接口）。掉线恢复时
    // 也必须发一次：`ServerStatus` 只有 `collection_changed` / `info` 会把连接
    // 改回「已连接」，否则状态行会一直停在「电脑未连接」。
    final collection =
        (id: view.activeCollectionId, name: view.activeCollectionName);
    if (wasOffline || _collection != collection) {
      _collection = collection;
      await updates.handle({
        'type': 'collection_changed',
        'collection_id': collection.id,
        'collection_name': collection.name,
      });
    }

    final fingerprint = (
      taskId: view.taskId ?? '',
      sessionId: view.sessionId ?? '',
      status: view.status,
      imageCount: view.imageCount,
      updatedAt: view.updatedAt,
    );
    final firstObservation = _last == null;
    // 状态没变：一条通知都不发（每秒重建一次列表会抖，用户也看不出区别）。
    //
    // 例外（M17 第 4 条）：**界面停在别的任务上**（签名非空且对不上）时必须补发
    // 一次 —— 上一次通知没落到界面上、或主机状态先到而后台丢了一轮时，指纹相同
    // 就再也不发，界面会永远停在旧内容上（用户原话：「当前任务又不直接刷新」）。
    // 界面签名为空（用户主动点过「忽略 / 知道了」）= 用户不想再看，不补发。
    final hostSignature = signatureOf(view);
    final ui = uiSignature?.call() ?? '';
    final uiStale =
        ui.isNotEmpty && hostSignature.isNotEmpty && ui != hostSignature;
    if (fingerprint == _last && !uiStale) return;
    _last = fingerprint;

    if (view.idle) return; // 空闲：只更新基线

    if (view.status == 'done' || view.status == 'failed') {
      // 冷启动第一次探测就看到终态 = 主机上一轮早在之前就结束了。只当基线，
      // 否则每打开一次 App 都会自动跳进上一次的结果页。
      // （WS 侧同样是「只补发进行中的任务」，两端口径一致。）
      if (firstObservation && !uiStale) return;
    }

    switch (view.status) {
      case 'queued':
      case 'analyzing':
        await updates.handle({
          'type': 'task_update',
          'task_id': fingerprint.taskId,
          'status': view.status,
          'session_id': view.sessionId,
          'image_count': view.imageCount,
        });
      case 'done':
        await _applyResult(view);
      case 'failed':
        await updates.handle({
          'type': 'task_failed',
          'task_id': fingerprint.taskId,
          'message': view.message,
        });
      default:
        // cancelled / 未知状态：协议向前兼容，忽略。
        break;
    }
  }

  /// `done`：复用 WS `task_result` 的落地路径（写会话 + 题目 + 页序 → 通知宿主）。
  Future<void> _applyResult(ActiveTaskView view) async {
    final raw = view.session;
    final sessionId = view.sessionId;
    if (raw == null || sessionId == null || sessionId.isEmpty) return;

    // M47：闩锁记的是「会话 + 结果版本」指纹，不再是裸的 session_id ——
    // 只记 session_id 时，同一会话的**新**结果（主机重新生成、或同图复用后再跑一次）
    // 会被永久吞掉，而 `protocol.md` 3.4.1 要求的判据是「这条结果已经在界面上」。
    final version = '${raw['updated_at'] ?? ''}|${raw['question_count'] ?? ''}';
    final fingerprint = '$sessionId|$version';
    if (_deliveredResult == fingerprint) return;

    // 之前这里按「本地库里已经有同版本结果」就跳过。那个条件太宽了（M17 第 4 条）：
    // 主机**同图复用**会复用同一个 session_id，手机本地早就有这条记录，但界面还
    // 停在上一轮 —— 于是轮询的 done 被静默丢掉，用户看到的就是「当前任务不刷新」。
    // 真正该问的是「这条结果**已经在界面上**了吗」，也就是界面签名一致。
    if (uiSignature?.call() == signatureOf(view)) {
      _deliveredResult = fingerprint;
      return;
    }

    _deliveredResult = fingerprint;
    await updates.handle({
      'type': 'task_result',
      'task_id': view.taskId ?? sessionId,
      'session': raw,
    });
  }

  /// 把端点返回的视图折成与「界面签名」同一个形状（拼法见 [taskSignature]）。
  static String signatureOf(ActiveTaskView view) => taskSignature(
      TaskState.parse(view.status), view.sessionId, view.imageCount);

  /// 探测失败：静默降级。
  void _applyFailure(Object error) {
    if (error is ApiClientException && error.code == 'revoked') {
      // token 失效 / 设备被吊销：与 WS 的 `device_revoked` 同一处理，
      // 必须让用户重新配对；再轮询下去也没意义。
      stop();
      _pairingKey = null;
      _deliveredResult = null;
      unawaited(updates.handle({'type': 'device_revoked'}));
      return;
    }
    // 已经是「未连接」时不重复刷状态行：一秒一次会把界面刷得一直重建。
    if (!_online) return;
    _online = false;
    // 只改状态行，不弹 SnackBar —— 一秒一次的失败提示会把界面炸了。
    updates.sink.offline(hostErrorMessage(error));
  }
}

/// 状态指纹。Dart record 天然按字段比较，`==` 就能判断「有没有变」，
/// 不必手写一堆字段对比。
typedef _TaskFingerprint = ({
  String taskId,
  String sessionId,
  String status,
  int imageCount,
  int updatedAt,
});

typedef _CollectionFingerprint = ({String? id, String? name});
