import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/android_capture_controller.dart';
import '../services/android_sync.dart';
import '../services/ball_settings.dart';
import '../services/capture_source.dart';
import '../services/host_gateway.dart';
import '../services/host_status_poller.dart';
import '../services/live_updates.dart';
import '../services/live_sync_service.dart';
import '../state/app_info.dart';
import '../state/app_state.dart';
import '../state/providers.dart';
import 'android_settings_page.dart';
import 'current_task_page.dart';
import 'history_page.dart';
import 'pairing_page.dart';
// `pickImageFromGallery` / `decodeImageBytes` 这两个顶层辅助函数住在
// `result_page.dart` 里（相册选图与结果页的手动重试共用）。
import 'result_page.dart';

/// Android 主壳（用户需求 6）：**底部三标签**「当前任务 / 历史记录 / 设置」，
/// 默认打开「当前任务」；同时负责悬浮球 / 截屏流程 / WS 自动刷新 / 相册上传。
class AndroidHomePage extends ConsumerStatefulWidget {
  final PairingInfo? pairing;

  /// 重新配对成功后回调（宿主更新自己持有的配对信息）。
  final void Function(PairingInfo info)? onRepaired;

  /// 解除配对 / 设备被吊销：宿主应回到配对页。
  final VoidCallback? onPairingLost;

  const AndroidHomePage({
    super.key,
    required this.pairing,
    this.onRepaired,
    this.onPairingLost,
  });

  @override
  ConsumerState<AndroidHomePage> createState() => _AndroidHomePageState();
}

class _AndroidHomePageState extends ConsumerState<AndroidHomePage>
    with WidgetsBindingObserver {
  late final AndroidCaptureController _captureController;
  late final LiveUpdates _liveUpdates;
  late final LiveSyncService _syncService;

  /// 轮询兜底（用户反馈 M15 第 4 条）：就算一条 WS 推送都没收到，
  /// 「当前任务」页也会自己跟上主机。
  late final HostStatusPoller _statusPoller;

  String? _imageDir;

  /// 是否有一次全量同步正在跑（防止启动补跑与重连补拉并发重复上传）。
  bool _syncing = false;

  /// 应用状态缓存成字段：dispose() 里不能再走 `ref`（widget 已销毁，
  /// Riverpod 会抛「Cannot use "ref" after the widget was disposed」）。
  late final AndroidAppState _app = ref.read(androidAppProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final app = _app;

    _liveUpdates = LiveUpdates(app: app, sink: RefLiveUpdateSink(ref));
    _syncService = LiveSyncService(
      app: app,
      onMessage: _liveUpdates.handle,
      // M14 第 6 条：WS 断线重连的窗口里，主机推的 `task_update` /
      // `task_result` 全丢了（用户看到「安卓端一点反应没有」）。连上就补拉一次。
      onReconnected: _onLiveSyncRestored,
    );
    // M15 第 4 条：轮询与 WS **共用同一个 LiveUpdates**，所以「识别中 / 自动进
    // 结果页 / 本机发起的识别静默」三条语义天然一致，不存在第二套 UI 逻辑。
    //
    // M17：再加两条 —— ① `uiSignature` 让轮询器能发现「界面停在别的任务上」
    // 并补发一次（用户第二次反馈「当前任务又不直接刷新」）；② `onRemoteOps`
    // 在主机本地 ops 水位上涨时让宿主**只拉一次** ops。
    //
    // M18 第 4 条：③ `onHostCollections` —— 主机每秒上报的「当前活跃合集列表」
    // 直接镜像进本地库（只增改不删）。用户反馈「安卓端识别不到 windows 端的分类」：
    // 合集原来只靠 ops 拉取落地，而拉取被 ops 水位这种间接信号触发，基线错一次就
    // 永久漏；改成按**想要的结果**对齐，差什么补什么。
    _statusPoller = HostStatusPoller(
      updates: _liveUpdates,
      probeFactory: ref.read(hostStatusProbeFactoryProvider),
      uiSignature: () => _uiTaskSignature(),
      onRemoteOps: () => unawaited(_pullRemoteOps()),
      onHostCollections: _mirrorHostCollections,
    );

    _captureController = AndroidCaptureController(
      app: app,
      captureSource: MethodChannelCaptureSource(),
      onResultReady: (sessionId) {
        if (!mounted) return;
        // 用户需求 3：识别全程静默——不跳「识别中」页、也不自动跳结果页，
        // 只把「当前任务」的状态与本地数据刷新掉（通知栏由控制器负责）。
        ref.read(activeTaskProvider.notifier).done(sessionId: sessionId);
        _invalidateLocalData();
      },
      onMessage: _snack,
    )
      ..onTaskSubmitted = ({required int imageCount, String? sessionId}) {
        // 用户需求 7：当前任务页显示「N 张图片识别中…」。
        // 用户需求 3：本机识别全程静默——**不切标签、不跳页**，
        // 只更新当前任务页的状态。
        ref.read(activeTaskProvider.notifier).begin(
              sessionId: sessionId,
              imageCount: imageCount,
            );
      };

    _initImageDir();
    app.settings.addListener(_onSettingsChanged);
    // initState 里不能改 provider（Riverpod 会抛「Tried to modify a provider
    // while the widget tree was building」），所以放到首帧之后再启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pairingProvider.notifier).state = widget.pairing;
      unawaited(_startup());
    });
  }

  Future<void> _initImageDir() async {
    String dir;
    try {
      final support = await getApplicationSupportDirectory();
      dir = '${support.path}/images';
    } catch (_) {
      // 平台未就绪（测试环境 / 存储不可用）时不要让未处理异常掀翻首屏。
      return;
    }
    if (!mounted) return;
    setState(() => _imageDir = dir);
    // 悬浮球截屏也要落盘，否则离线补跑取不到原图（队列会卡死）；
    // 存完顺带清理最旧的原图（M14 第 7 条：安卓端固定只留最近 20 张）。
    _captureController.saveImageFile = (hash, bytes) async {
      final sync = AndroidSync(app: _app, imageDir: dir);
      await sync.saveImageFile(hash, bytes);
      await sync.pruneImages();
    };
  }

  /// 启动：探测主机 + 按识别模块开关决定悬浮球与 WS + 补跑离线队列。
  Future<void> _startup() async {
    unawaited(ref.read(serverStatusProvider.notifier).refresh(widget.pairing));
    await _applyRecognitionState();
    if (widget.pairing == null) return;
    try {
      final notified = await CaptureBridgeCalls.requestNotificationPermission();
      if (!notified) {
        _snack('建议授予通知权限，保持截屏服务常驻（设置 → 识别模块设置）');
      }
    } catch (_) {}
    unawaited(_backgroundSync());
  }

  /// 识别模块开关（用户需求 11）：关着时**悬浮球不显示**、也不连主机。
  Future<void> _applyRecognitionState() async {
    // 轮询只在「已配对 + 前台」时才需要，与识别模块开关无关：识别模块关掉时
    // 「当前任务」页仍然是 Windows 的结果显示器，照样要能自己刷新。
    _applyPollingState();
    final app = _app;
    final pairing = widget.pairing;
    final enabled = app.settings.app.androidRecognitionEnabled;
    final useWs = ref.read(liveSyncEnabledProvider);
    try {
      if (pairing != null && enabled) {
        final appearance = await BallAppearance.load(app.repo);
        await CaptureBridgeCalls.setBallAppearance(
            opacity: appearance.opacity, sizeDp: appearance.sizeDp);
        // M47：尊重「显示悬浮球」开关（`recognition_settings_page` 里落库的那个）。
        // 原来这里无条件把球打开，用户关掉球之后只要改任何一项设置就又冒出来。
        final ballWanted = await BallAppearance.loadEnabled(app.repo);
        final availability = await MethodChannelCaptureSource().availability();
        if (!availability.overlayGranted) {
          if (ballWanted) {
            _snack('悬浮窗权限未授予：请到「设置 → 识别模块设置 → 权限设置」开启后再打开悬浮球');
          }
        } else {
          final shown = await CaptureBridgeCalls.setBallVisible(ballWanted);
          if (ballWanted && !shown) _snack('悬浮球显示失败：请检查悬浮窗权限');
        }
        if (useWs) _syncService.start(pairing);
      } else {
        await CaptureBridgeCalls.setBallVisible(false);
        _syncService.stop();
      }
    } catch (_) {
      // 平台通道未就绪（测试环境 / 插件缺失）：不阻断主界面。
    }
  }

  @override
  void didUpdateWidget(AndroidHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pairing?.token != widget.pairing?.token) {
      // 重新配对会换掉 token：宿主必须同步更新，否则所有上传都还在用旧
      // token（表现为「Windows 不在线」）。didUpdateWidget 同样不能直接改
      // provider，统一放到帧后。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pairingProvider.notifier).state = widget.pairing;
        unawaited(_applyRecognitionState());
        unawaited(
            ref.read(serverStatusProvider.notifier).refresh(widget.pairing));
      });
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    ref.read(settingsRevisionProvider.notifier).state++;
    setState(() {});
    unawaited(_applyRecognitionState());
  }

  /// 轮询的启停（用户反馈 M15 第 4 条）。
  ///
  /// 配对成功且 App 在前台时跑；取消配对 / 进后台时停。重复调用是安全的
  /// （`HostStatusPoller.start` 只重启定时器、保留同一配对的基线）。
  void _applyPollingState() {
    final pairing = widget.pairing;
    if (pairing != null &&
        ref.read(hostPollingEnabledProvider) &&
        _inForeground) {
      _statusPoller.start(pairing);
    } else {
      _statusPoller.stop();
    }
  }

  /// 与 `shouldAutoOpenResult` 同一口径：还没收到生命周期事件（首帧 / 测试）
  /// 与 `inactive` 都按前台处理。
  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 悬浮球在后台完成分析时必须能改走「发通知」分支。
    _captureController.appInBackground = state != AppLifecycleState.resumed;
    // 后台不必每秒去打扰主机；回前台立刻恢复（基线保留，后台期间的结果不会丢）。
    _applyPollingState();
    if (state == AppLifecycleState.resumed) {
      // M49：回到前台时丢掉积压的提示（后台期间的消息已由系统 Toast 显示过，
      // 见 `_snack`），否则用户一回来就要把攒下的提示逐条看完。
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      unawaited(ref.read(serverStatusProvider.notifier).refresh(widget.pairing));
    }
  }

  /// 应用内轻提示。
  ///
  /// M49（用户反馈「识别期间攒下的提示，回到应用后一个一个跳出来，直到结束」）：
  /// 提示是**瞬时**反馈，不该排队。两条规则：
  /// ① 人在别的应用里时**不入队** —— 悬浮球手势期间 App 在后台，每条提示都已经
  ///    由 `AndroidCaptureController._notify` 以系统 Toast 显示过（用户当时就看到了），
  ///    回来再逐条回放纯粹是延迟骚扰；
  /// ② 在前台也只留**最新一条** —— `ScaffoldMessenger` 的队列是「一条 4 秒」串行
  ///    播放，连按几次悬浮球就要看上十几秒（`clearSnackBars` 丢掉积压的旧提示）。
  void _snack(String message) {
    if (!mounted) return;
    if (_captureController.appInBackground) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// WS 重新连上（含首次连上）后的补齐（M14 第 6 条）。
  ///
  /// 只靠长连接推送是不够的：断线期间主机产生的本机任务状态与结果不会重发，
  /// 重连后必须自己「先拉后推」补一次，界面才会跟上。
  Future<void> _onLiveSyncRestored() async {
    if (!mounted) return;
    unawaited(ref.read(serverStatusProvider.notifier).refresh(widget.pairing));
    // 安静地跑：重连可能很频繁，不能每次都弹提示。
    await _backgroundSync(quiet: true);
    // 即使这一轮没拉到东西也让界面重新读一次本地库：连上本身可能意味着
    // 刚刚错过了一次写入。
    if (mounted) _invalidateLocalData();
  }

  /// [quiet] = true 时不弹「已同步」提示（WS 重连路径用）。
  Future<void> _backgroundSync({bool quiet = false}) async {
    final pairing = widget.pairing;
    if (pairing == null) return;
    // 同一时刻只允许一次全量同步：启动补跑与「首次连上」的重连回调几乎同时
    // 发生，两次并发跑会把离线队列里的同一条任务上传两遍。
    if (_syncing) return;
    _syncing = true;
    try {
      final support = await getApplicationSupportDirectory();
      final sync = AndroidSync(app: _app, imageDir: '${support.path}/images');
      final r = await sync.runFull(pairing);
      if (r.drained > 0 || r.pulled > 0 || r.pushed > 0) {
        _invalidateLocalData();
        if (!quiet) {
          _snack('已同步：补跑 ${r.drained} 条 · 拉取 ${r.pulled} · 推送 ${r.pushed}');
        }
      }
    } catch (_) {
      // 主机不在线 / 存储不可用：下次再试。
    } finally {
      _syncing = false;
    }
  }

  void _invalidateLocalData() {
    ref.invalidate(sessionsProvider);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionGroupsProvider);
    ref.invalidate(unclassifiedSessionsProvider);
    ref.invalidate(sessionQuestionsProvider);
    ref.invalidate(sessionImagesProvider);
    ref.invalidate(sessionProvider);
  }

  /// 界面当前展示的任务签名（与主机侧 `HostStatusPoller.signatureOf` 同拼法）。
  String _uiTaskSignature() {
    try {
      return activeTaskSignature(ref.read(activeTaskProvider));
    } catch (_) {
      return '';
    }
  }

  /// 主机的本地 ops 水位涨了 → 只拉一次 ops（M17 第 5 条）。
  ///
  /// 防抖：主机一次批量写入会让水位连着涨几级，一次拉取就够了（拉取自身按
  /// 游标增量返回，重复调用也不重复落地）。
  bool _pullingOps = false;

  /// 主机上报的合集列表 → 镜像进本地库（M18 第 4 条）。
  ///
  /// 用户原话：「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」。
  /// 这条不依赖 WS、也不依赖 ops 水位：只要 1 秒一次的轮询在跑，主机上新建/改名
  /// 的合集就会出现在手机「历史」里（只增改，不删 —— 主机删掉的合集在手机保留）。
  Future<void> _mirrorHostCollections(List<Collection> collections) async {
    final changed =
        await AndroidSync(app: _app, imageDir: _imageDir ?? '')
            .mirrorHostCollections(collections);
    if (changed > 0 && mounted) _invalidateLocalData();
  }

  Future<void> _pullRemoteOps() async {
    final pairing = widget.pairing;
    if (pairing == null || _pullingOps) return;
    _pullingOps = true;
    try {
      final support = await getApplicationSupportDirectory();
      final sync = AndroidSync(app: _app, imageDir: '${support.path}/images');
      final pulled = await sync.pullOpsOnly(pairing);
      if (pulled > 0 && mounted) _invalidateLocalData();
    } catch (_) {
      // 主机不在线 / 平台未就绪：水位下次再涨时还会拉。
    } finally {
      _pullingOps = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.settings.removeListener(_onSettingsChanged);
    _captureController.dispose();
    _syncService.stop();
    _statusPoller.stop();
    unawaited(CaptureBridgeCalls.setBallVisible(false));
    super.dispose();
  }

  // ------------------------------------------------------------
  // 入口
  // ------------------------------------------------------------

  Future<void> _openPairing() async {
    // Navigator 先取好：onPaired 是在配对页里异步回调的，闭包里不能保证
    // 还能用 `context`（State 被销毁时 Navigator.of 会抛）。
    final navigator = Navigator.of(context);
    late final MaterialPageRoute<bool> route;
    route = MaterialPageRoute<bool>(
        builder: (_) => PairingPage(
              app: _app,
              onPaired: (info) {
                // 重新配对会作废旧 token：立刻把新的配对信息交给宿主。
                widget.onRepaired?.call(info);
                // 用户反馈 M14 第 5 条：配对成功后要「跳转到当前任务」——
                // 标签已由配对页切到 0，这里再把配对页收掉，用户才真的回到
                // 主界面（DECISIONS.md 里「推入场景仍走 pop」的本意，
                // pop(true) 同时让下面那句 SnackBar 生效）。
                // `isCurrent` 防止用户在配对请求返回前手动返回后又被弹一次
                // （那会把整个主界面弹掉）。
                if (mounted && route.isCurrent) navigator.pop(true);
              },
            ));
    final ok = await navigator.push<bool>(route);
    if (ok == true && mounted) {
      _snack('已用新配对信息重新连接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(androidAppProvider);
    final pairing = widget.pairing;
    final tab = ref.watch(tabIndexProvider);
    ref.watch(settingsRevisionProvider);
    final recognitionEnabled = app.settings.app.androidRecognitionEnabled;
    final status = ref.watch(serverStatusProvider);
    final canUpload =
        pairing != null && recognitionEnabled && status.hasActiveCollection;
    final hostName = status.info?.deviceName.isNotEmpty == true
        ? status.info!.deviceName
        : (pairing == null || pairing.serverName.isEmpty
            ? pairing?.host
            : pairing.serverName);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kAppName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: pairing == null
                        ? Theme.of(context).colorScheme.error
                        : (status.online
                            ? HighlightColors.lightText
                            : Theme.of(context).colorScheme.outline),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  pairing == null
                      ? '未配对'
                      : (status.online ? '已连接 $hostName' : '电脑未连接'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('repair'),
            tooltip: '重新配对',
            icon: const Icon(Icons.link),
            onPressed: _openPairing,
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: [
          // 用户需求 1：当前任务页只显示 Windows 的任务结果，
          // 本机识别的一切入口都在「设置 → 识别模块」。
          const CurrentTaskPage(),
          const HistoryTab(),
          AndroidSettingsPage(
            onUnpair: () async {
              await _app.clearPairing();
              await CaptureBridgeCalls.setBallVisible(false);
              widget.onPairingLost?.call();
            },
          ),
        ],
      ),
      floatingActionButton: (tab == 0 && canUpload)
          ? FloatingActionButton.extended(
              key: const ValueKey('pick-from-gallery'),
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('相册选图搜题'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) =>
            ref.read(tabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            key: ValueKey('tab-current'),
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: '当前任务',
          ),
          NavigationDestination(
            key: ValueKey('tab-history'),
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史记录',
          ),
          NavigationDestination(
            key: ValueKey('tab-settings'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // 相册选图（用户需求 11：识别模块关着时入口不可用）
  // ------------------------------------------------------------

  Future<void> _pickAndUpload() async {
    final pairing = widget.pairing;
    if (pairing == null) {
      _snack('请先与电脑配对');
      return;
    }
    if (!_app.settings.app.androidRecognitionEnabled) {
      _snack('识别模块已关闭：请先在「设置 → 识别模块」打开');
      return;
    }
    final status = ref.read(serverStatusProvider);
    if (status.online && !status.hasActiveCollection) {
      // 用户需求 12：先确认主机已选合集，不静默失败。
      // 不切标签也不跳页：本机识别一律静默（用户需求 3）。
      _snack(kNoActiveCollectionMessage);
      return;
    }

    // 选图必须在 try 里：image_picker 抛 PlatformException（无权限/无相册
    // 应用/被系统拦截）时原来会变成未处理异常，用户点按钮「毫无反应」。
    Uint8List? picked;
    try {
      picked = await pickImageFromGallery();
    } catch (e) {
      _snack('打开相册失败：$e（可改用悬浮球截屏）');
      return;
    }
    if (picked == null || !mounted) return;

    Uint8List jpeg = picked;
    // 统一压缩规格：JPEG、长边 ≤ 1600、质量 80（SPEC 2.1）。
    final decoded = decodeImageBytes(picked);
    if (decoded != null) {
      final processed =
          ImageProc.toJpeg(decoded.bgra, decoded.width, decoded.height);
      jpeg = processed.jpeg;
    }

    ref.read(activeTaskProvider.notifier).begin(imageCount: 1);
    // 用户需求 3：相册选图也走静默路径——不压「识别中」页，
    // 采集与上传在后台完成，「当前任务」页自然更新。
    final result = await _uploadFromGallery(pairing, jpeg);
    if (!mounted) return;
    if (result.ok && result.sessionId != null) {
      ref.read(activeTaskProvider.notifier).done(sessionId: result.sessionId);
    } else {
      ref.read(activeTaskProvider.notifier).failed(result.message);
    }
    _invalidateLocalData();
  }

  /// 相册路径：上传分析 → 转成 [CaptureResult] 供「识别中」页面使用；
  /// 主机不在线时入离线队列（data-model.md 2.8）。
  Future<CaptureResult> _uploadFromGallery(
      PairingInfo pairing, Uint8List jpeg) async {
    final dir = _imageDir ??
        '${(await getApplicationSupportDirectory()).path}/images';
    final saver = AndroidSync(app: _app, imageDir: dir).saveImageFile;
    final collectionId = ref.read(serverStatusProvider).activeCollectionId;
    final api = ApiClient(baseUrl: pairing.httpBase, token: pairing.token);
    try {
      final outcome = await uploadAndAnalyze(
        api,
        _app.repo,
        jpeg,
        deviceId: _app.repo.deviceId,
        saveFile: saver,
        collectionId: collectionId,
      );
      if (outcome.ok) return CaptureResult.ok(outcome.sessionId);
      return CaptureResult.failed(
          outcome.errorMessage ?? outcome.errorCode ?? '分析失败');
    } on ApiClientException catch (e) {
      if (e.code == 'revoked') {
        await _app.clearPairing();
        return const CaptureResult.failed('已解除配对，请重新扫码');
      }
      if (isNoActiveCollection(e)) {
        return CaptureResult.failed(kNoActiveCollectionMessage);
      }
      return CaptureResult.failed('上传失败：${e.message}');
    } catch (_) {
      // 主机不在线 → 入离线队列，等 Windows 上线后补跑。
      final hash = sha256Hex(jpeg);
      await _app.repo.upsertImage(ImageMeta(
        hash: hash,
        size: jpeg.length,
        mime: 'image/jpeg',
        createdAt: nowMs(),
        uploadedBy: _app.repo.deviceId,
      ));
      try {
        await _app.queue.enqueue(
          imageHash: hash,
          sourceDevice: _app.repo.deviceId,
          collectionId: collectionId,
        );
      } on QueueFullException catch (e) {
        return CaptureResult.failed('$e');
      }
      return const CaptureResult.failed('Windows 不在线，已排队，上线后自动分析');
    }
  }
}

/// WS 事件 → Riverpod（用户需求 1/7：主机开始识别后自动刷新，不靠手动下拉）。
///
/// 公开类型（而不是私有 `_RefSink`）是为了让 widget 测试能直接构造它，
/// 断言「一条 `task_update` / `task_result` 消息就能让当前任务页更新」。
class RefLiveUpdateSink implements LiveUpdateSink {
  RefLiveUpdateSink(this.ref);

  final WidgetRef ref;

  void _invalidateLocalData() {
    ref.invalidate(sessionsProvider);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionGroupsProvider);
    ref.invalidate(unclassifiedSessionsProvider);
    ref.invalidate(sessionQuestionsProvider);
    ref.invalidate(sessionImagesProvider);
    ref.invalidate(sessionProvider);
  }

  @override
  void collectionChanged(String? collectionId, String? collectionName) => ref
      .read(serverStatusProvider.notifier)
      .applyCollection(collectionId, collectionName);

  @override
  void serverInfo(ServerInfo info) =>
      ref.read(serverStatusProvider.notifier).applyInfo(info);

  @override
  void taskUpdate({
    required String taskId,
    required TaskState status,
    String? sessionId,
    int imageCount = 0,
  }) {
    ref.read(activeTaskProvider.notifier).update(
          taskId: taskId,
          status: status,
          sessionId: sessionId,
          imageCount: imageCount,
        );
    _invalidateLocalData();
  }

  @override
  void taskResult({
    required String sessionId,
    required int questionCount,
    bool selfInitiated = false,
  }) {
    // 用户需求 3：主机发起的识别完成后自动进入结果页；本机自己发起的识别
    // 保持静默（主机也会把这条结果广播回来，不能因此跳页）。
    ref
        .read(activeTaskProvider.notifier)
        .done(sessionId: sessionId, autoOpen: !selfInitiated);
    _invalidateLocalData();
  }

  @override
  void taskFailed({required String taskId, String? message}) {
    ref.read(activeTaskProvider.notifier).failed(message ?? '分析失败');
    _invalidateLocalData();
  }

  @override
  void offline(String message) =>
      ref.read(serverStatusProvider.notifier).offline(message);

  @override
  void dataChanged() => _invalidateLocalData();

  @override
  void deviceRevoked() {
    ref.read(pairingProvider.notifier).state = null;
    ref.read(serverStatusProvider.notifier).reset();
    _invalidateLocalData();
  }
}

/// 常驻免责声明（SPEC 4.4）。
class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('答案由 AI 生成，仅供参考',
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}
