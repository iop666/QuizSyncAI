import 'constants.dart';

/// 状态块的数据（纯值对象，方便单测直接断言渲染结果）。
class StatusView {
  final bool running;
  final String ip;
  final int? port;

  /// 配对码（过期前一直显示）。
  final String pairingCode;

  /// 已通过 WebSocket 连着的设备名（空 = 还没有手机连上）。
  final List<String> connectedDevices;

  /// 已配对过、但当前没连着的设备名。
  final List<String> pairedDevices;

  final String providerLabel;
  final String model;
  final bool aiConfigured;

  /// 两个动作当前生效的热键文案（如 `F8（备用 Alt+Shift+Q）`）。
  final String captureLabel;
  final String multipageLabel;

  /// 多页模式已抓张数（0 = 不在多页模式）。
  final int pendingPages;
  final int maxPages;

  /// 数据目录（配置/历史/图片都在这里）。
  final String dataDir;

  /// 启动标识：第几次启动 + 上次启动时间（人读文本，空 = 不显示）。
  final String runInfo;

  const StatusView({
    required this.running,
    required this.ip,
    required this.port,
    required this.pairingCode,
    this.connectedDevices = const [],
    this.pairedDevices = const [],
    required this.providerLabel,
    required this.model,
    required this.aiConfigured,
    required this.captureLabel,
    required this.multipageLabel,
    this.pendingPages = 0,
    this.maxPages = kHardMaxPagesPerTask,
    this.dataDir = '',
    this.runInfo = '',
  });
}

/// 渲染状态块（中文、紧凑；一眼看完，不刷屏）。
List<String> renderStatusLines(StatusView v) {
  final connected = v.connectedDevices.isNotEmpty;
  final lines = <String>[
    '$kServerProductName v$kServerVersion',
    '─' * 46,
    _row('服务器', v.running ? '运行中' : '已停止',
        '${v.ip.isEmpty ? '(未获取到 IP)' : v.ip}:${v.port ?? '-'}'),
    _row(
        '手机',
        !v.running
            ? '已停止'
            : connected
                ? '已连接'
                : '等待配对',
        connected
            ? v.connectedDevices.join('、')
            : '配对码 ${v.pairingCode}'
                '${v.pairedDevices.isEmpty ? '' : '（已配对：${v.pairedDevices.join('、')}）'}'),
    _row('AI', v.aiConfigured ? '已配置' : '未配置',
        '${v.providerLabel} · ${v.model}'),
    _row('热键', '截屏识别', v.captureLabel),
    _row('', '多页模式', v.multipageLabel),
  ];
  if (v.pendingPages > 0) {
    lines.add(_row('多页', '已抓 ${v.pendingPages}/${v.maxPages} 张', '按识别键立即上传识别'));
  }
  if (v.runInfo.isNotEmpty) {
    lines.add(_row('运行', '', v.runInfo));
  }
  if (v.dataDir.isNotEmpty) {
    lines.add(_row('数据', '', v.dataDir));
  }
  return lines;
}

/// 一行的排法：`  服务器  运行中    192.168.1.2:8765`。
String _row(String label, String state, String detail) {
  final l = _pad(label, 8);
  final s = state.isEmpty ? '' : _pad(state, 10);
  return '  $l$s$detail'.trimRight();
}

/// 中英文混排按「显示宽度」补空格（中文算 2 列），否则状态列参差不齐。
String _pad(String text, int width) {
  var w = 0;
  for (final rune in text.runes) {
    w += rune > 0x2E80 ? 2 : 1;
  }
  final fill = width - w;
  return fill <= 0 ? '$text ' : '$text${' ' * fill}';
}
