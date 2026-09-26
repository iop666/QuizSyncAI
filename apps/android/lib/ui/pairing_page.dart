import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/capture_source.dart';
import '../state/app_info.dart';
import '../state/app_state.dart';
import '../state/providers.dart';

/// 扫码视图构造：默认是真实的 [MobileScanner]。
///
/// 允许注入的原因：本机没有安卓设备/模拟器，测试里创建真实相机会失败
/// （平台通道不可用）。有了这个缝，「首次进入不自动扫码、点击后才启动」
/// 这条用户需求 7 的流程才能被单测覆盖。
typedef ScannerViewBuilder = Widget Function(
    BuildContext context, ValueChanged<String> onDetected);

/// 配对页（SPEC 3.4 / protocol.md 2）：扫码 / 粘贴配对链接 / 手动输入。
///
/// 用户需求 7：**首次进入不初始化相机、不申请权限**。先给说明与一个
/// 「开始使用」按钮，用户点了才申请相机权限；被拒给明确提示与重试/去设置
/// 的入口；授权成功后才真正启动扫码。方式二（粘贴链接）与方式三（手动输入）
/// 始终可用，不依赖相机。
///
/// 用户需求 D2：页面上是三个并列模块——方式一「扫码」、方式二「粘贴配对链接」、
/// 方式三「手动输入」；粘贴入口不再塞在扫码模块里。
///
/// 作为初始页使用时传 [onPaired]（成功后回调，由父级切换到主页）；
/// 作为路由推入时可不传（成功后 pop(true)）。
class PairingPage extends ConsumerStatefulWidget {
  final AndroidAppState app;
  final ValueChanged<PairingInfo>? onPaired;
  final ScannerViewBuilder? scannerBuilder;

  const PairingPage({
    super.key,
    required this.app,
    this.onPaired,
    this.scannerBuilder,
  });

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  final _manualHost = TextEditingController();
  final _manualPort = TextEditingController(text: '8765');
  final _manualCode = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _status;

  /// 扫码是否已启动（用户需求 7：默认 false —— 相机一次都不碰）。
  bool _scanActive = false;

  /// 相机权限被拒：给明确的提示 + 重试入口。
  bool _cameraDenied = false;

  /// 权限申请进行中（防连点）。
  bool _requestingCamera = false;

  @override
  void dispose() {
    _manualHost.dispose();
    _manualPort.dispose();
    _manualCode.dispose();
    super.dispose();
  }

  /// 「开始使用」：先申请相机权限，授权成功才启动扫码。
  Future<void> _startScanning() async {
    if (_requestingCamera) return;
    setState(() {
      _requestingCamera = true;
      _error = null;
    });
    final granted = await CaptureBridgeCalls.requestCameraPermission();
    if (!mounted) return;
    setState(() {
      _requestingCamera = false;
      _cameraDenied = !granted;
      _scanActive = granted;
    });
  }

  Future<void> _pair({required String host, required int port, required String code}) async {
    // 扫码回调会连续触发多次：没有这道闸门就会重复 POST /pair，
    // 第二次可能因限速被拒（「尝试过于频繁」），或者把刚拿到的 token 作废。
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在连接 $host:$port …';
    });
    try {
      final probe = ref.read(pairingClientFactoryProvider)('http://$host:$port');
      final info = await probe.fetchInfo();
      setState(() => _status = '已找到电脑「${info.deviceName}」，正在配对…');
      final resp = await probe.pair(PairRequest(
        code: code,
        deviceId: widget.app.repo.deviceId,
        deviceName: 'Android 手机',
        platform: 'android',
        // M46 第 4 条：报给主机的是**本机真实版本**（主机在「连接设备」里显示它）。
        appVersion: kAppVersion,
      ));
      // protocol.md 3.1：ai_configured=false 只提示、不阻止配对。
      final pairing = PairingInfo(
        host: host,
        port: port,
        token: resp.token,
        serverDeviceId: resp.serverDeviceId,
        serverName: resp.serverName,
      );
      await widget.app.savePairing(pairing);
      // 用户反馈 M14 第 5 条：配对成功后一律回到「当前任务」标签。
      // 扫码 / 粘贴配对链接 / 手动输入三条路径都在 `_pair` 这里汇合，
      // 所以只写这一处；重点是「设置 → 连接设备」里重新配对的场景——
      // 用户回来时不该还停在设置标签（首次配对进主界面本来就是 0）。
      // 这里是异步回调、不在 build 期间，可以直接改 provider。
      if (mounted) ref.read(tabIndexProvider.notifier).state = 0;
      if (mounted && !info.aiConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已配对，但主机尚未配置 AI：请先在 Windows 端设置 API Key'),
        ));
      }
      if (widget.onPaired != null) {
        widget.onPaired!(pairing);
      } else if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiClientException catch (e) {
      setState(() => _error = switch (e.code) {
          'invalid_code' => '配对码错误，请核对 Windows 端显示的 6 位数字',
          'code_expired' => '配对码已过期，请在 Windows 端点「刷新」后重试',
          'rate_limited' => '尝试过于频繁，${e.retryAfterSeconds ?? 60} 秒后再试',
          'network_error' || 'timeout' => '连不上这台电脑：确认手机与电脑在同一 Wi-Fi、'
              '防火墙放行该端口，且地址填写正确',
          _ => '配对失败：${e.message}',
        });
    } catch (e) {
      setState(() => _error = '无法连接主机：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// 从剪贴板粘贴配对链接（桌面端「复制配对链接」按钮产出的同一串内容）。
  /// 相机不可用 / 屏幕小看不清时，这是最快的通路。
  Future<void> _pairFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = '剪贴板里没有内容：请先在电脑端设置页点「复制配对链接」');
      return;
    }
    final parsed = parsePairQr(text);
    if (parsed == null) {
      setState(() => _error = '剪贴板内容不是配对链接（应以 quizsync://pair? 开头）');
      return;
    }
    await _pair(host: parsed.host, port: parsed.port, code: parsed.code);
  }

  /// 真实扫码视图：权限已由 `_startScanning` 拿到，这里只负责取二维码内容。
  Widget _buildScanner(BuildContext context, ValueChanged<String> onDetected) {
    return MobileScanner(
      // 出错时给出可见信息（相机占用/被系统回收等），不留黑屏。
      errorBuilder: (context, error, child) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          '相机不可用（${error.errorCode.name}）\n'
          '请检查相机权限，或改用下面的方式二 / 方式三',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw == null) return;
        onDetected(raw);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scannerBuilder = widget.scannerBuilder ?? _buildScanner;
    return Scaffold(
      appBar: AppBar(title: const Text('与 Windows 配对')),
      body: _busy
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(_status ?? '正在配对…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.wifi, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '电脑和手机需要在同一个 Wi-Fi 下。\n'
                            'Windows 端：设置 → 连接设备 → 显示二维码与 6 位配对码。',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  title: '方式一：扫码',
                  icon: Icons.qr_code_scanner,
                  children: [
                    if (!_scanActive) ...[
                      // 用户需求 7：先说明、后授权，绝不自动调起相机。
                      Text(
                        '点击下面的按钮才会申请相机权限并打开扫码。'
                        '不授权也不影响配对：方式二 / 方式三随时可用。',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        key: const ValueKey('start-scan'),
                        onPressed: _requestingCamera ? null : _startScanning,
                        icon: _requestingCamera
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(_requestingCamera ? '正在申请权限…' : '开始使用（扫码配对）'),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46)),
                      ),
                    ] else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: SizedBox(
                          height: 240,
                          width: double.infinity,
                          child: scannerBuilder(context, (raw) {
                            final parsed = parsePairQr(raw);
                            if (parsed == null) return;
                            _pair(
                                host: parsed.host,
                                port: parsed.port,
                                code: parsed.code);
                          }),
                        ),
                      ),
                    if (_cameraDenied) ...[
                      const SizedBox(height: AppSpacing.md),
                      Card(
                        key: const ValueKey('camera-denied'),
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.5),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.no_photography_outlined,
                                      size: 18,
                                      color: theme.colorScheme.error),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '相机权限未授予，无法扫码。可以点「重新申请」；'
                                      '若系统已不再弹出授权框，就到系统设置里'
                                      '为 QuizSync 打开相机权限，或改用方式二 / 方式三。',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  FilledButton(
                                    key: const ValueKey('retry-scan-permission'),
                                    onPressed:
                                        _requestingCamera ? null : _startScanning,
                                    child: const Text('重新申请'),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  OutlinedButton(
                                    key: const ValueKey('open-camera-settings'),
                                    onPressed: () =>
                                        CaptureBridgeCalls.openAppSettings(),
                                    child: const Text('去系统设置'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // 用户需求 D2：「粘贴配对链接」从方式一里拆出来，单独成一个模块，
                // 与扫码互不遮挡（相机不可用时它就是最快的通路）。
                SectionCard(
                  title: '方式二：粘贴配对链接',
                  subtitle: '先在电脑端点「复制配对链接」，再回到这里粘贴。',
                  icon: Icons.content_paste_go,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('paste-pair-link'),
                      onPressed: _pairFromClipboard,
                      icon: const Icon(Icons.content_paste_go, size: 18),
                      label: const Text('粘贴配对链接'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  title: '方式三：手动输入',
                  subtitle: '地址与配对码都在 Windows 端设置页的「连接设备」里。',
                  icon: Icons.keyboard_outlined,
                  children: [
                    TextField(
                      controller: _manualHost,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: '主机地址（如 192.168.1.23）'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualPort,
                            decoration: const InputDecoration(labelText: '端口'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _manualCode,
                            decoration:
                                const InputDecoration(labelText: '6 位配对码'),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: () {
                        final host = _manualHost.text.trim();
                        final port = int.tryParse(_manualPort.text.trim()) ?? 8765;
                        final code = _manualCode.text.trim();
                        if (host.isEmpty) {
                          setState(() => _error = '请填写电脑的局域网地址');
                          return;
                        }
                        if (code.length != 6) {
                          setState(() => _error = '配对码是 6 位数字，请核对');
                          return;
                        }
                        _pair(host: host, port: port, code: code);
                      },
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('开始配对'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46)),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(height: 1.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
