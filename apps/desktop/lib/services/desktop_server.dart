import 'dart:io';
import 'dart:typed_data';

import 'package:quizsync_core/quizsync_core.dart';

import '../state/app_info.dart' show kAppVersion;
import '../state/settings.dart' show AiUiSettings;

/// 桌面端内置服务端的持有者（M4）。
class DesktopServerController {
  QuizSyncServer? server;
  int? port;
  String? error;

  bool get isRunning => server != null;

  /// 在线的设备数：WS 连着的 + 最近有过已认证请求的（手机轮询走 HTTP）。
  int get activeDeviceCount => server?.activeDeviceCount ?? 0;

  Future<void> start({
    required CoreRepository repo,
    required Map<String, QuizAiProvider> registry,
    required AiUiSettings Function() aiSettingsReader,
    required Future<String?> Function() keyReader,
    required String imageDir,
    int preferredPort = 8765,
    void Function(String status, String? sessionId)? onTaskUpdate,
  }) async {
    if (server != null) return;
    final store = DirectoryImageStore(imageDir);
    final engine = AnalysisEngine(
      provider: _ActiveProvider(registry, keyReader),
      cache: AnalysisCache(repo),
      quota: QuotaGuard(repo.db, dailyLimit: aiSettingsReader().dailyLimit),
      deviceId: repo.deviceId,
    );
    final executor = ServerTaskExecutor(
      repo: repo,
      engine: engine,
      imageStore: store,
      // 任务执行时实时读设置与 Key。修：此前在启动时快照 aiSettings 且
      // apiKey 恒为空串，_execute 的「未配置」检查必然命中，导致手机提交
      // 的任务全部失败「主机尚未配置 AI」。
      configProvider: () async {
        final ai = aiSettingsReader();
        final key = await keyReader();
        return AiConfig(
          providerId: ai.providerId,
          baseUrl: ai.baseUrl,
          apiKey: key ?? '',
          model: ai.model,
          timeoutSeconds: ai.timeoutSeconds,
        );
      },
    );
    final host = Platform.localHostname;
    final s = QuizSyncServer(
      repo: repo,
      imageStore: store,
      executor: executor,
      deviceId: repo.deviceId,
      serverName: host,
      options: QuizSyncServerOptions(
          preferredPort: preferredPort,
          // M46 第 4 条：主机自报的版本跟着产品版本走（「关于」页、`/info` 的
          // `app_version`、响应头 `X-QS-Server-Version` 三处同源）。
          appVersion: kAppVersion),
    );
    // 用户反馈 12：手机提交的任务也要让 Windows 端「显示识别界面」。
    s.onTaskUpdateHook = onTaskUpdate;
    try {
      port = await s.start();
      server = s;
      error = null;
    } catch (e) {
      error = e.toString();
      server = null;
    }
  }

  Future<void> stop() async {
    await server?.stop();
    server = null;
    port = null;
  }

  /// 桌面端切换/新建合集后通知安卓端（用户需求 12）。
  Future<void> notifyCollectionChanged() async {
    await server?.notifyCollectionChanged();
  }

  /// 桌面端**本地**截屏的状态广播（用户反馈 2）：手机端据此显示
  /// 「N 张图片识别中…」，完成后自动加载结果。
  void notifyLocalSession(String sessionId, String status,
      {int imageCount = 0}) {
    server?.notifyLocalSession(sessionId, status, imageCount: imageCount);
  }

  /// 当前选中的合集 id（服务端与设置页共用同一份判定）。
  Future<String?> activeCollectionId() async {
    final s = server;
    if (s == null) return null;
    return (await s.activeCollection())?.collectionId;
  }

  /// 二维码内容（protocol.md 2.1）。
  String qrPayload(String lanIp) {
    final s = server;
    if (s == null || port == null) return '';
    return 'quizsync://pair?host=$lanIp&port=$port&code=${s.pairingCode}&sid=${s.deviceId}&v=1';
  }
}

/// 动态读取当前 key 的 provider 包装（key 在安全存储里，随取随用）。
class _ActiveProvider extends QuizAiProvider {
  final Map<String, QuizAiProvider> registry;
  final Future<String?> Function() keyReader;

  _ActiveProvider(this.registry, this.keyReader);

  @override
  String get id => 'active';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    final key = await keyReader();
    final real = registry[config.providerId] ?? registry.values.first;
    return real.analyze(
      jpegBytesList: jpegBytesList,
      prompt: prompt,
      config: config.copyWith(apiKey: key ?? ''),
    );
  }
}

/// 获取本机局域网 IPv4（配对二维码用）。
///
/// 注意：`NetworkInterface.list()` 的顺序不保证，装了 Hyper-V / WSL / Docker /
/// VMware / VirtualBox 的机器上第一个非环回地址往往是**虚拟网卡**，二维码里
/// 就会写进一个手机永远连不上的 IP（表现为「扫码后连接超时」）。所以这里优先
/// 取物理网卡上的私有地址，虚拟网卡只作兜底。
Future<String> lanIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    final preferred = <String>[];
    final fallback = <String>[];
    for (final it in interfaces) {
      final name = it.name.toLowerCase();
      final virtual = _virtualAdapterHints.any(name.contains);
      for (final addr in it.addresses) {
        if (addr.isLoopback || !_isPrivateV4(addr.address)) continue;
        (virtual ? fallback : preferred).add(addr.address);
      }
    }
    if (preferred.isNotEmpty) return preferred.first;
    if (fallback.isNotEmpty) return fallback.first;
  } catch (_) {}
  return '127.0.0.1';
}

const _virtualAdapterHints = [
  'vethernet', 'hyper-v', 'wsl', 'vmware', 'virtualbox', 'vbox',
  'docker', 'loopback', 'bluetooth', 'tap', 'tun', 'utun',
];

/// RFC1918 私有地址（局域网可达的地址基本都在这个范围）。
bool _isPrivateV4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
