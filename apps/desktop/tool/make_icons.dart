// 生成桌面端图标资源（一次性工具，产物已提交）：
//   cd apps/desktop && dart run tool/make_icons.dart
//
// 输入（仓库根目录 icon/，用户提供的品牌图）：
//   icon/QuizSync_AI.png  应用程序图标源图（1254×1254）——窗口/任务栏/安装包用
//   icon/Statusbar.png    状态栏（托盘）图标源图（636×636）
//   icon/FloatingBall_Default.png            悬浮球：待识别
//   icon/FloatingBall_DetectionInProgress.png 悬浮球：识别中
//   icon/FloatingBall_MultiPageMode.png      悬浮球：多页模式
//
// 输出：
//   assets/app_icon.png                     关于页用的 256×256 应用图标（带圆角）
//   windows/runner/resources/app_icon.ico   应用程序图标（多尺寸，**带圆角**）
//   assets/statusbar.ico                    托盘图标（多尺寸：16/20/24/32/48/64/128
//                                           用 BMP 帧，256 用 PNG 帧 —— LoadImage
//                                           (SM_CYSMICON) 对 BMP 帧最稳）
//   assets/floating_ball_*.png              悬浮球三态（256×256，**圆形 + 透明底**）
//
// 用户反馈 1（M11）：Windows 任务栏图标不是圆角。Windows 不会替应用图标自动
// 加圆角，所以这里在生成时就把方图裁成圆角（alpha 遮罩，带抗锯齿），
// 任务栏、Alt+Tab、开始菜单、文件资源管理器里看到的都会是圆角。
//
// 用户反馈 1（M12）：**状态栏（托盘）图标也还是方的**。源图 `Statusbar.png`
// 是「白底 + 蓝色字形」（实测四角 (254,254,254) 不透明），托盘里就是一个白
// 方块。这里对它套上和应用图标同一套 22% 圆角遮罩 —— 托盘、任务栏角落看到的
// 都是圆角图标。
//
// 用户反馈 11（M12）：悬浮球三张源图也是**白底不透明**（白底占比 40%），
// 直接缩放上去会是一个白方块。这里先把**球外部的白底**按连通域去掉（球内部
// 的白色字形保留），再套圆形遮罩，得到可直接放到任意尺寸的透明圆形 PNG。
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 需要写进 ICO 的尺寸（像素）。
const _bmpSizes = [16, 20, 24, 32, 40, 48, 64, 128];
const _pngSizes = [256];

/// 圆角半径 = 尺寸 × 该比例（Windows 11 系图标观感约 22%）。
const double _cornerRatio = 0.22;

/// 悬浮球 PNG 资源边长（运行时等比缩放到用户设置的大小，够用且不浪费）。
const int _ballSize = 256;

/// 悬浮球三态：源图 → 资源名。
const Map<String, String> _ballSources = {
  'FloatingBall_Default.png': 'assets/floating_ball_default.png',
  'FloatingBall_DetectionInProgress.png': 'assets/floating_ball_detecting.png',
  'FloatingBall_MultiPageMode.png': 'assets/floating_ball_multipage.png',
};

void main() {
  final appSource = _find('QuizSync_AI.png');
  final statusSource = _find('Statusbar.png');
  stdout.writeln('应用图标源图：$appSource');
  stdout.writeln('托盘图标源图：$statusSource');

  final appRaw = _decode(appSource);
  final statusRaw = _decode(statusSource);

  final outDir = Directory('assets')..createSync(recursive: true);

  // ---------------------------------------------------------------
  // 1. 应用程序图标（用户反馈 1：任务栏要圆角；用户反馈 4：关于页用应用图标）
  // ---------------------------------------------------------------
  final appIcon = _rounded(appRaw, 256);
  final appPng = File('${outDir.path}/app_icon.png')
    ..writeAsBytesSync(img.encodePng(appIcon));

  final appIco = _buildIco(_framesOf(appRaw));
  final appIcoFile = File('windows/runner/resources/app_icon.ico')
    ..writeAsBytesSync(appIco);

  // ---------------------------------------------------------------
  // 2. 托盘（状态栏）图标：与应用图标同一套圆角（用户反馈 1，本轮）
  // ---------------------------------------------------------------
  final statusIco = _buildIco(_framesOf(statusRaw));
  final statusIcoFile = File('${outDir.path}/statusbar.ico')
    ..writeAsBytesSync(statusIco);

  // ---------------------------------------------------------------
  // 3. 悬浮球三态（用户反馈 11）：去白底 + 圆形
  // ---------------------------------------------------------------
  final ballReports = <String>[];
  for (final entry in _ballSources.entries) {
    final src = _decode(_find(entry.key));
    final ball = _circularBall(src, _ballSize);
    final file = File(entry.value)..writeAsBytesSync(img.encodePng(ball));
    final stats = _alphaStats(ball);
    ballReports.add('${entry.value.padRight(44)} ${file.lengthSync()} B  '
        '不透明 ${stats.$1}% 边缘透明 ${stats.$2}%');
  }

  stdout.writeln('assets/app_icon.png                          '
      '${appPng.lengthSync()} B');
  stdout.writeln('windows/runner/resources/app_icon.ico        '
      '${appIcoFile.lengthSync()} B');
  stdout.writeln('assets/statusbar.ico                         '
      '${statusIcoFile.lengthSync()} B');
  for (final r in ballReports) {
    stdout.writeln(r);
  }
}

/// 悬浮球资源：先按连通域去白底，再套圆形遮罩。返回 [size]×[size]。
///
/// 为什么不做「整图按颜色去白」：球**内部**的白色字形也会被一起抠掉。
/// 从四边做洪水填充只影响「和画布边框连通」的白，球内白字原样保留。
img.Image _circularBall(img.Image source, int size) {
  final im = img.copyResize(source,
      width: size, height: size, interpolation: img.Interpolation.cubic);
  _removeOuterWhite(im);
  final (cx, cy, r) = _discBounds(im);
  final mask = _circleMask(size, cx, cy, r);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = im.getPixel(x, y);
      final a = (p.a * mask[y * size + x] / 255).round().clamp(0, 255);
      im.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }
  return im;
}

bool _whiteish(img.Pixel p) {
  final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
  final maxv = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minv = r < g ? (r < b ? r : b) : (g < b ? g : b);
  return minv >= 222 && (maxv - minv) <= 14;
}

/// 从画布四边洪水填充，把「与边框连通的白/近白」变成全透明。
void _removeOuterWhite(img.Image im) {
  final w = im.width, h = im.height;
  final seen = Uint8List(w * h);
  final queue = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i] != 0) return;
    seen[i] = 1;
    if (!_whiteish(im.getPixel(x, y))) return;
    queue.add(i);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    final x = i % w, y = i ~/ w;
    final p = im.getPixel(x, y);
    im.setPixelRgba(x, y, p.r, p.g, p.b, 0);
    push(x - 1, y);
    push(x + 1, y);
    push(x, y - 1);
    push(x, y + 1);
  }
}

/// 量出球体的圆心与半径（用剩余不透明像素的包围盒，比假设「正好内切」稳）。
(double, double, double) _discBounds(img.Image im) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a < 40) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return (im.width / 2, im.height / 2, im.width / 2);
  final cx = (minX + maxX + 1) / 2;
  final cy = (minY + maxY + 1) / 2;
  final r = ((maxX - minX + 1) + (maxY - minY + 1)) / 4;
  return (cx, cy, r);
}

/// 圆形覆盖率遮罩（0–255，3×3 超采样抗锯齿）。
Uint8List _circleMask(int size, double cx, double cy, double r) {
  const ss = 3;
  final mask = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var hits = 0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final dx = x + (sx + 0.5) / ss - cx;
          final dy = y + (sy + 0.5) / ss - cy;
          if (dx * dx + dy * dy <= r * r) hits++;
        }
      }
      mask[y * size + x] = (255 * hits / (ss * ss)).round();
    }
  }
  return mask;
}

/// (不透明占比, 边缘透明占比) —— 只为生成时自检打印。
(int, int) _alphaStats(img.Image im) {
  var opaque = 0;
  final w = im.width, h = im.height;
  for (final p in im) {
    if (p.a >= 200) opaque++;
  }
  var edge = 0, edgeTotal = 0;
  for (var x = 0; x < w; x++) {
    for (final y in [0, h - 1]) {
      edgeTotal++;
      if (im.getPixel(x, y).a < 8) edge++;
    }
  }
  return ((opaque * 100 / (w * h)).round(), (edge * 100 / edgeTotal).round());
}

String _find(String name) {
  for (final candidate in [
    'icon/$name',
    '../icon/$name',
    '../../icon/$name',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  stderr.writeln('找不到 $name（请在 apps/desktop 目录下运行本工具）');
  exit(1);
}

img.Image _decode(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('无法解码 $path');
    exit(1);
  }
  return decoded.convert(numChannels: 4);
}

/// 缩放 + 圆角透明遮罩（抗锯齿）。
img.Image _rounded(img.Image source, int size) {
  final resized = img.copyResize(source,
      width: size, height: size, interpolation: img.Interpolation.cubic);
  final radius = size * _cornerRatio;
  final mask = _roundedMask(size, radius);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = resized.getPixel(x, y);
      final a = (p.a * mask[y * size + x] / 255).round().clamp(0, 255);
      resized.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }
  return resized;
}

/// 圆角矩形覆盖率（0–255）。每像素 3×3 超采样，边缘不会有锯齿。
Uint8List _roundedMask(int size, double radius) {
  const ss = 3;
  final mask = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var hits = 0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final px = x + (sx + 0.5) / ss;
          final py = y + (sy + 0.5) / ss;
          if (_insideRoundedRect(px, py, size, radius)) hits++;
        }
      }
      mask[y * size + x] = (255 * hits / (ss * ss)).round();
    }
  }
  return mask;
}

bool _insideRoundedRect(double px, double py, int size, double r) {
  final cx = px.clamp(r, size - r).toDouble();
  final cy = py.clamp(r, size - r).toDouble();
  final dx = px - cx;
  final dy = py - cy;
  return dx * dx + dy * dy <= r * r;
}

/// 所有尺寸的帧，统一带圆角（应用图标与托盘图标都是圆角，用户反馈 1）。
List<_Frame> _framesOf(img.Image source) {
  final frames = <_Frame>[];
  for (final size in _bmpSizes) {
    frames.add(_Frame(size, _dibOf(_rounded(source, size)), isPng: false));
  }
  for (final size in _pngSizes) {
    frames.add(_Frame(size, img.encodePng(_rounded(source, size)), isPng: true));
  }
  return frames;
}
/// 单帧：BMP(DIB) 或 PNG 数据 + 尺寸。
class _Frame {
  final int size;
  final Uint8List data;
  final bool isPng;
  _Frame(this.size, this.data, {required this.isPng});
}

/// 32bpp 的 DIB（BITMAPINFOHEADER + 自下而上的 BGRA + AND 掩码）。
/// ICO 里的 BMP 帧必须是「高度翻倍」的格式，透明度靠 alpha + 掩码两套都写。
Uint8List _dibOf(img.Image image) {
  final w = image.width;
  final h = image.height;
  final maskRowBytes = ((w + 31) ~/ 32) * 4; // 1bpp 行按 4 字节对齐
  final maskBytes = maskRowBytes * h;
  final pixelBytes = w * h * 4;
  final out = BytesBuilder();

  // BITMAPINFOHEADER
  final header = ByteData(40);
  header.setUint32(0, 40, Endian.little); // biSize
  header.setInt32(4, w, Endian.little); // biWidth
  header.setInt32(8, h * 2, Endian.little); // biHeight（含掩码）
  header.setUint16(12, 1, Endian.little); // biPlanes
  header.setUint16(14, 32, Endian.little); // biBitCount
  header.setUint32(16, 0, Endian.little); // biCompression = BI_RGB
  header.setUint32(20, pixelBytes + maskBytes, Endian.little); // biSizeImage
  out.add(header.buffer.asUint8List());

  // 像素：自下而上
  final pixels = Uint8List(pixelBytes);
  var p = 0;
  for (var y = h - 1; y >= 0; y--) {
    for (var x = 0; x < w; x++) {
      final c = image.getPixel(x, y);
      pixels[p++] = c.b.toInt();
      pixels[p++] = c.g.toInt();
      pixels[p++] = c.r.toInt();
      pixels[p++] = c.a.toInt();
    }
  }
  out.add(pixels);

  // AND 掩码：alpha < 128 记为透明（1）
  final mask = Uint8List(maskBytes);
  for (var y = 0; y < h; y++) {
    final srcY = h - 1 - y;
    final rowStart = y * maskRowBytes;
    for (var x = 0; x < w; x++) {
      if (image.getPixel(x, srcY).a < 128) {
        mask[rowStart + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  out.add(mask);
  return out.toBytes();
}

/// 组 ICO 文件（ICONDIR + ICONDIRENTRY[] + 各帧数据）。
Uint8List _buildIco(List<_Frame> frames) {
  const headerSize = 6;
  const entrySize = 16;
  var offset = headerSize + entrySize * frames.length;
  final entries = BytesBuilder();
  final data = BytesBuilder();

  for (final f in frames) {
    final e = ByteData(entrySize);
    e.setUint8(0, f.size >= 256 ? 0 : f.size); // 256 记 0
    e.setUint8(1, f.size >= 256 ? 0 : f.size);
    e.setUint8(2, 0); // 调色板数
    e.setUint8(3, 0); // 保留
    e.setUint16(4, 1, Endian.little); // 平面数
    e.setUint16(6, 32, Endian.little); // 位深
    e.setUint32(8, f.data.length, Endian.little); // 数据长度
    e.setUint32(12, offset, Endian.little); // 数据偏移
    entries.add(e.buffer.asUint8List());
    data.add(f.data);
    offset += f.data.length;
  }

  final head = ByteData(headerSize);
  head.setUint16(0, 0, Endian.little); // reserved
  head.setUint16(2, 1, Endian.little); // type = icon
  head.setUint16(4, frames.length, Endian.little);

  return (BytesBuilder()
        ..add(head.buffer.asUint8List())
        ..add(entries.toBytes())
        ..add(data.toBytes()))
      .toBytes();
}
