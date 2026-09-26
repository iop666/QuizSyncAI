import 'dart:io';

/// 本机局域网 IPv4（配对二维码 / CLI 面板用）。
///
/// 照搬主项目 `apps/desktop/lib/services/desktop_server.dart` 的取法：
/// `NetworkInterface.list()` 的顺序不保证，装了 Hyper-V / WSL / Docker / VMware
/// 的机器上第一个非环回地址往往是**虚拟网卡**，二维码里就会写进一个手机永远
/// 连不上的 IP（表现：扫码后连接超时）。所以优先取物理网卡的私有地址，
/// 虚拟网卡只作兜底。
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
        if (addr.isLoopback || !isPrivateV4(addr.address)) continue;
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
bool isPrivateV4(String ip) {
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
