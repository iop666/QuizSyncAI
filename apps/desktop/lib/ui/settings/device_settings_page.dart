import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/desktop_server.dart';
import '../../state/app_scope.dart';

/// 连接设备（M9）：服务状态、二维码配对、已配对设备。
/// 原来的「服务（Android 配对）」整块搬到这里，配对/吊销逻辑不变；
/// 新增的只是「当前连接状态」这一块——数据来自服务端真实的 WS 连接数。
class DeviceSettingsPage extends ConsumerStatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  ConsumerState<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

/// 「同一时间只支持一台安卓设备」的说明（M49 用户反馈：设置里要写清楚）。
///
/// 这不是随口写的限制：两端 `device_id` 都是固定字面量（安卓 `android-local`、
/// Windows `windows-local`），配对、token、WS 槽位、在线计数全以它为主键 ——
/// 第二台手机扫码会**覆盖**同一行的 token hash，第一台立刻掉线（而且手机端
/// 只有收到 `revoked` 才提示重新配对，它只会显示「电脑未连接」）。所以这里
/// 明确告诉用户换手机的正确顺序。
const String kSingleAndroidDeviceNote =
    '同一时间只支持连接一台安卓设备。换手机时请先在下方「已配对设备」里吊销旧设备，'
    '再用新手机扫码配对；直接配对新手机，旧手机会立刻掉线并需要重新扫码。';

class _DeviceSettingsPageState extends ConsumerState<DeviceSettingsPage> {
  String? _lanIp;
  int _refreshTick = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    lanIpAddress().then((ip) {
      if (mounted) setState(() => _lanIp = ip);
    });
    // 用户反馈 8：一进「连接设备」页就自动刷新配对码与二维码
    // （配对码 5 分钟过期，用户往往就是过期后才进来，进来看到新的最省事）。
    _refreshPairing();
    // 配对码倒计时与连接状态都要自己走秒，否则这个页面显示的是打开那一刻的快照。
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// 刷新配对码（二维码内容跟着变）；服务未启动时什么都不做。
  void _refreshPairing() {
    final server = ref.read(serverControllerProvider).server;
    if (server == null) return;
    server.refreshPairingCode();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 打开 / 关闭局域网连接（M32 用户需求 3）。
  ///
  /// 关着的时候内置服务端根本不启动（不监听端口）；打开时才启动 —— Windows 会
  /// 在这个时候弹防火墙授权窗口，也就是需求里说的「获取网络权限来授权」。
  Future<void> _toggleConnect(bool value) async {
    final app = ref.read(settingsProvider).app;
    await ref.read(settingsProvider).updateApp(app.copyWith(connectEnabled: value));
    await ref.read(connectToggleProvider)(value);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? '已开启局域网连接：服务启动中，若弹出防火墙提示请选「允许访问」'
            : '已关闭局域网连接：服务已停止，不再监听任何端口')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = ref.watch(settingsProvider).app;
    final enabled = app.connectEnabled;
    final controller = ref.watch(serverControllerProvider);
    final server = controller.server;

    // 用户需求 3：总开关关着时，下方功能全部不可用（连服务端都不启动）。
    final switchGroup = SettingsGroup(
      title: '局域网连接',
      icon: Icons.wifi_tethering,
      children: [
        SettingsRow(
          key: const ValueKey('settings-connect-switch'),
          title: '开启连接设备',
          subtitle: enabled
              ? (server == null ? '已开启：服务正在启动…' : '已开启：局域网服务运行中')
              : '已关闭（默认）：不启动服务、不监听任何端口',
          info: '连接设备默认关闭。关闭时这台电脑不会监听任何端口，手机也连不上；'
              '打开时才启动内置服务并申请网络权限（Windows 会弹一次防火墙授权，'
              '请选「允许访问」）。关掉开关会立刻停掉服务，正在连接的手机也会断开。',
          trailing: SettingsSwitch(
            value: enabled,
            onChanged: _toggleConnect,
          ),
        ),
        if (!enabled)
          const SettingsNote(
            text: '连接设备已关闭：下面的配对码、二维码与设备列表都不可用。'
                '需要手机上传题目时，先打开这个开关并完成配对。',
            warn: false,
          ),
      ],
    );

    if (!enabled) {
      return SettingsSection(
        title: '连接设备',
        description: '手机与电脑需在同一局域网；打开开关并扫码配对后，'
            '手机就能把题目发到这台电脑识别。',
        children: [
          switchGroup,
          SettingsGroup(
            title: '配对与设备',
            icon: Icons.lock_outline,
            showDividers: false,
            children: const [
              SettingsRow(
                key: ValueKey('settings-connect-disabled'),
                title: '当前不可用',
                subtitle: '打开上面的「开启连接设备」后，这里会显示配对码、二维码与已配对设备',
              ),
            ],
          ),
          const SettingsNote(text: kSingleAndroidDeviceNote),
        ],
      );
    }

    if (server == null) {
      return SettingsSection(
        title: '连接设备',
        description: '手机与电脑需要连在同一个局域网。',
        children: [
          switchGroup,
          SettingsGroup(
            title: '当前连接状态',
            icon: Icons.lan_outlined,
            showDividers: false,
            children: [
              _statusCard(
                context,
                color: scheme.error,
                status: '服务未启动',
                detail: controller.error ?? '端口被占用或未配置',
              ),
              const SettingsNote(
                text: '手机无法连接时，先确认 Windows 防火墙放行 8765–8770 端口。',
                warn: true,
              ),
            ],
          ),
          const SettingsNote(text: kSingleAndroidDeviceNote),
        ],
      );
    }

    final port = controller.port;
    final payload = controller.qrPayload(_lanIp ?? '127.0.0.1');
    final remain = server.pairingExpiresAt - nowMs();
    final remainSeconds = remain <= 0 ? 0 : (remain / 1000).ceil();
    // M47（用户实测反馈）：「在线」判据不能只看 WS 连接数 —— 手机端在前台时是
    // 每秒一次的 HTTP 轮询（HostStatusPoller），不建 WS，原来的 `connectedCount`
    // 会让设置页一直停在「等待手机连接」。
    final online = server.activeDeviceCount;
    final devicesAsync = ref.watch(_devicesProvider(_refreshTick));
    final devices = devicesAsync.valueOrNull ?? const <DeviceInfo>[];

    return SettingsSection(
      title: '连接设备',
      description: '手机与电脑需在同一局域网；扫码或手动输入地址 + 配对码即可配对。',
      children: [
        switchGroup,
        SettingsGroup(
          title: '当前连接状态',
          children: [
            _statusCard(
              context,
              color: online > 0
                  ? HighlightColors.text(theme.brightness == Brightness.dark)
                  : scheme.onSurfaceVariant,
              status: online > 0 ? '已连接' : '等待手机连接',
              detail: online > 0
                  ? '$online 台设备在线 · ${_lanIp ?? '…'}:$port'
                  : '服务已启动（${_lanIp ?? '…'}:$port），手机扫码后会显示在这里',
            ),
          ],
        ),
        SettingsGroup(
          title: '设备配对',
          icon: Icons.qr_code_2,
          children: [
            _pairingCard(context, server, payload, port, remainSeconds),
          ],
        ),
        SettingsGroup(
          title: '已配对设备',
          icon: Icons.devices_other,
          trailing: IconButton(
            key: const ValueKey('settings-devices-refresh'),
            tooltip: '刷新列表',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => setState(() => _refreshTick++),
          ),
          children: [
            if (devicesAsync.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SettingsGap.s16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (devicesAsync.hasError)
              SettingsRow(title: '读取失败', subtitle: '${devicesAsync.error}')
            else if (devices.isEmpty)
              SettingsRow(
                title: '暂无设备',
                subtitle: '手机扫码配对后会出现在这里',
              )
            else
              for (final d in devices)
                SettingsRow(
                  icon: d.platform == 'android'
                      ? Icons.phone_android
                      : Icons.computer,
                  title: d.name,
                  subtitle: '${d.platform} · ${d.isRevoked ? '已吊销' : '已配对'}'
                      '${d.appVersion == null ? '' : ' · v${d.appVersion}'}',
                  trailing: d.isRevoked
                      ? null
                      : TextButton(
                          key: ValueKey('settings-device-revoke-${d.deviceId}'),
                          onPressed: () => _confirmRevoke(d),
                          child: const Text('吊销'),
                        ),
                ),
          ],
        ),
        // M49：「同时只能一台安卓」的说明（放在整段最后，服务未启动时也看得到）。
        const SettingsNote(text: kSingleAndroidDeviceNote),
      ],
    );
  }

  /// 配对区：二维码 + 配对码 + 链接。窗口变窄时二维码与说明自动改为上下排列
  /// （窗口最小宽度 860，左侧收成图标栏后内容区会明显变窄，横向排不下）。
  Widget _pairingCard(BuildContext context, QuizSyncServer server,
      String payload, int? port, int remainSeconds) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final qr = Container(
      padding: const EdgeInsets.all(SettingsGap.s8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: QuizSyncTheme.outline(theme.brightness)),
      ),
      child: QrImageView(
        data: payload,
        version: QrVersions.auto,
        size: 148,
        backgroundColor: Colors.white,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: SettingsGap.s8,
          runSpacing: SettingsGap.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('配对码', style: SettingsType.rowSubtitle(scheme)),
            Text(
              server.pairingCode,
              key: const ValueKey('pairing-code'),
              style: TextStyle(
                fontSize: 26,
                height: 1.2,
                letterSpacing: 6,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            IconButton(
              tooltip: '复制配对码',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => _copy(server.pairingCode, '配对码已复制'),
            ),
            IconButton(
              key: const ValueKey('settings-pairing-refresh-code'),
              tooltip: '刷新配对码',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _refreshPairing,
            ),
          ],
        ),
        const SizedBox(height: SettingsGap.s8),
        StatusPill(
          icon: remainSeconds > 0
              ? Icons.timer_outlined
              : Icons.timer_off_outlined,
          label: remainSeconds > 0
              ? '${_formatRemain(remainSeconds)}后过期'
              : '已过期，请点刷新',
          color: remainSeconds > 0 ? scheme.primary : scheme.error,
        ),
        const SizedBox(height: SettingsGap.s16),
        Wrap(
          spacing: SettingsGap.s16,
          runSpacing: SettingsGap.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('settings-copy-pair-link'),
              onPressed: () => _copy(payload, '配对链接已复制'),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('复制配对链接'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  icon: Icons.lan_outlined,
                  label: '${_lanIp ?? '…'}:$port',
                  color: scheme.onSurfaceVariant,
                  filled: false,
                ),
                IconButton(
                  tooltip: '复制地址',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copy('${_lanIp ?? ''}:$port', '地址已复制'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: SettingsGap.s8),
        Text('手机相机不方便扫码时，把配对链接发给手机，在配对页用「方式二：粘贴配对链接」。',
            style: SettingsType.aux(scheme)),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SettingsGap.s16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [qr, const SizedBox(height: SettingsGap.s24), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              const SizedBox(width: SettingsGap.s32),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  /// 连接状态行（**不再自己画一张卡**：它已经在一个 SettingsGroup 模块卡片里，
  /// 用户反馈 3「每个模块都有两个背景」就是这两层白底叠出来的）。
  Widget _statusCard(
    BuildContext context, {
    required Color color,
    required String status,
    required String detail,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SettingsGap.s16),
      child: Row(
        children: [
          SettingsStatusDot(color: color),
          const SizedBox(width: SettingsGap.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status,
                    style: TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const SizedBox(height: 2),
                Text(detail, style: SettingsType.rowSubtitle(scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
  }

  /// 吊销要二次确认，并且走服务端通知对端（否则手机还以为自己连着）。
  Future<void> _confirmRevoke(DeviceInfo d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('吊销这台设备？'),
        content: Text('${d.name}\n吊销后它的 token 立即失效，手机端需要重新扫码配对。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('吊销')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final server = ref.read(serverControllerProvider).server;
    if (server != null) {
      await server.revokeDeviceAndNotify(d.deviceId);
    } else {
      await ref.read(repoProvider).revokeDevice(d.deviceId);
    }
    if (!mounted) return;
    setState(() => _refreshTick++);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已吊销 ${d.name}')));
  }

  String _formatRemain(int seconds) {
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '$m 分 ${s.toString().padLeft(2, '0')} 秒';
    }
    return '$seconds 秒';
  }
}

final _devicesProvider =
    FutureProvider.family.autoDispose<List<DeviceInfo>, int>((ref, tick) {
  return ref.watch(repoProvider).listDevices();
});
