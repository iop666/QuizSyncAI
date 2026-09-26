/// 在纯文本 CLI 里显示配对二维码。
///
/// 需求要求「Android 用**现有扫码功能**连接」，而 Server 没有 GUI ——
/// 唯一的办法就是在终端里把二维码画出来。做法与 `qrencode -t ANSIUTF8` 一致：
/// 用上半块字符 `▀`，前景色 = 上面那个模块、背景色 = 下面那个模块，
/// 于是两个模块高只用一行、一个模块宽用一个字符（45×45 的码约 49 列宽，
/// 80 列的终端放得下）。
///
/// 注意：终端字体必须是等宽且包含 `▀`（Consolas / 更纱黑体 等都可以）；
/// 扫不出来时把终端字号调小一点，或直接用面板上的 6 位配对码手动配对。
library;

import 'package:qr/qr.dart';

/// 二维码矩阵（true = 深色模块）。
QrImage qrImageOf(String data) {
  final code = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  return QrImage(code);
}

/// 渲染成可直接打印的多行文本。
///
/// [useAnsi] 为 true 时用 ANSI 黑白配色（推荐，扫码率高）；false 时退化成
/// `██` / 两个空格（给不支持转义的终端 / 单测用）。
/// [quietZone] 是四周留白（模块数），协议要求至少 4；终端里给 2 就够，
/// 因为终端本身有背景色对比。
List<String> renderQrLines(
  String data, {
  bool useAnsi = true,
  int quietZone = 2,
}) {
  final image = qrImageOf(data);
  final size = image.moduleCount;
  final lines = <String>[];

  bool dark(int row, int col) {
    if (row < 0 || col < 0 || row >= size || col >= size) return false;
    return image.isDark(row, col);
  }

  for (var y = -quietZone; y < size + quietZone; y += 2) {
    final sb = StringBuffer();
    if (useAnsi) {
      for (var x = -quietZone; x < size + quietZone; x++) {
        final top = dark(y, x);
        final bottom = dark(y + 1, x);
        // 30/40 = 黑，37/47 = 白；`▀` 的上半用前景色、下半用背景色。
        sb.write('\x1b[3${top ? 0 : 7};4${bottom ? 0 : 7}m\u2580');
      }
      sb.write('\x1b[0m');
    } else {
      for (var x = -quietZone; x < size + quietZone; x++) {
        sb.write(dark(y, x) ? '\u2588\u2588' : '  ');
      }
    }
    lines.add(sb.toString());
  }
  return lines;
}

/// 配对二维码内容（protocol.md 2.1，**必须**与 Desktop 版逐字一致，
/// 否则 Android 解析不出来）。
String pairQrPayload({
  required String host,
  required int port,
  required String code,
  required String serverDeviceId,
}) =>
    'quizsync://pair?host=$host&port=$port&code=$code&sid=$serverDeviceId&v=1';
