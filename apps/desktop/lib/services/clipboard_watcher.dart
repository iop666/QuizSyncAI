import 'dart:ffi';
import 'dart:typed_data';

import 'package:win32/win32.dart';

/// 剪贴板监听（SPEC 2.1：检测到新图片自动分析）。
/// 用 `GetClipboardSequenceNumber` 轮询（零拷贝、开销极小），
/// 序列号变化且存在 CF_DIB / CF_BITMAP 时取图，按内容 hash 去重。
class ClipboardWatcher {
  final void Function(CapturedImage image) onImage;
  final Duration interval;

  int _lastSeq = -1;
  String? _lastHash;
  bool _running = false;

  ClipboardWatcher({required this.onImage, this.interval = const Duration(milliseconds: 700)});

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    Future(doPoll);
  }

  void stop() => _running = false;

  Future<void> doPoll() async {
    while (_running) {
      await Future<void>.delayed(interval);
      if (!_running) return;
      try {
        _pollOnce();
      } catch (_) {
        // 剪贴板被其他进程占用等情况直接跳过本轮。
      }
    }
  }

  void _pollOnce() {
    final seq = GetClipboardSequenceNumber();
    if (seq == 0 || seq == _lastSeq) return;
    _lastSeq = seq;

    final image = _readClipboardDib();
    if (image == null) return;
    if (_lastHash == image.contentHash) {
      return; // 同一张图不反复触发
    }
    _lastHash = image.contentHash;
    onImage(image);
  }
}

/// 托盘菜单「从剪贴板读取」：立即取一次当前剪贴板图片（不看去重）。
/// 无图片或剪贴板被占用时返回 null。
CapturedImage? readClipboardImageNow() => _readClipboardDib();

/// 读取当前剪贴板里的 DIB 图片；失败返回 null。
///
/// 修（用户反馈 M14 第 3 条「剪贴板监听毫无作用」）：原来先枚举格式、发现
/// CF_DIB/CF_DIBV5 存在，就只 `GetClipboardData(CF_DIB)`。实测（本机用
/// PowerShell 的 `Clipboard.SetImage` 放一张真图，再枚举剪贴板）看到：
/// CF_DIB 确实存在，但它的 `biCompression = 3 = BI_BITFIELDS`（现代截图工具 /
/// 浏览器 / .NET 都用带掩码的 32bpp DIB），而旧解析只认 `BI_RGB`，
/// 于是**每一步都成功、最后一步静默返回 null** —— 用户看到的就是「毫无作用」。
/// 现在：CF_DIB → CF_DIBV5 依次尝试，并按 DIB 里的掩码取通道。
CapturedImage? _readClipboardDib() {
  if (OpenClipboard(0) == 0) return null;
  try {
    for (final format in const [CF_DIB, CF_DIBV5]) {
      final image = _readDibFormat(format);
      if (image != null) return image;
    }
    // 只有 CF_BITMAP 时理论上还能用 GetDIBits 取像素，但那种剪贴板（老程序
    // 只放 GDI 句柄、不放 DIB）现在基本绝迹，且 `GlobalLock` 对位图句柄
    // 只会返回 null —— 与其写一条无法在本机复现的路径，不如在这里停下。
    return null;
  } finally {
    CloseClipboard();
  }
}

/// 读某一种 DIB 格式（CF_DIB = 40 字节头，CF_DIBV5 = 124 字节头）。
CapturedImage? _readDibFormat(int format) {
  final handle = GetClipboardData(format);
  if (handle == 0) return null;
  final hMem = Pointer.fromAddress(handle);
  final ptr = GlobalLock(hMem);
  if (ptr == nullptr) return null;
  try {
    // GlobalSize 对剪贴板内存句柄**不保证准确**（文档明确说可能大于申请值），
    // 所以先照 DIB 头自己算「这张图需要多少字节」，再取实际可用的较小值，
    // 避免按一个偏小的 GlobalSize 截断像素（那会得到半张图或直接解析失败）。
    final available = GlobalSize(hMem);
    final probe = ptr.cast<Uint8>().asTypedList(available >= 40 ? 40 : available);
    final need = _dibByteLength(probe);
    if (need == null) return null;
    final size = available >= need ? need : available;
    if (size < need) return null;
    final bytes = ptr.cast<Uint8>().asTypedList(size);
    return parseClipboardDib(Uint8List.fromList(bytes));
  } finally {
    GlobalUnlock(hMem);
  }
}

/// BI_RGB：像素按 BGR(A) 排布，无掩码。
const int _biRgb = 0;

/// BI_BITFIELDS：调用方给了通道掩码（现代剪贴板的常见形态）。
const int _biBitfields = 3;

/// 从 DIB 头算出「整张图需要多少字节」（头 + 掩码 + 像素行，行按 4 字节对齐）。
/// 头本身不合法时返回 null。
int? _dibByteLength(Uint8List head) {
  if (head.length < 40) return null;
  final headerSize = _readU32(head, 0);
  final width = _readI32(head, 4);
  final height = _readI32(head, 8);
  final planes = _readU16(head, 12);
  final bitCount = _readU16(head, 14);
  final compression = _readU32(head, 16);
  if (headerSize < 40 || width <= 0 || height == 0 || planes != 1) return null;
  if (compression != _biRgb && compression != _biBitfields) return null;
  if (bitCount != 24 && bitCount != 32) return null;
  var offset = headerSize;
  // 40 字节头 + BI_BITFIELDS 时，三个掩码紧跟在头后面（V4/V5 头的掩码在头内部）。
  if (compression == _biBitfields && headerSize == 40) offset += 12;
  final bytesPerRow = ((width * bitCount + 31) ~/ 32) * 4;
  return offset + bytesPerRow * height.abs();
}

/// 解析 DIB（BITMAPINFOHEADER / V4 / V5，BI_RGB 或 BI_BITFIELDS，24/32bpp）。
///
/// 公开是为了让单测能直接喂构造出来的 DIB 字节（真实剪贴板内容无法在测试里
/// 稳定复现）；业务代码只经 [readClipboardImageNow] / [ClipboardWatcher] 使用。
CapturedImage? parseClipboardDib(Uint8List dib) {
  if (dib.length < 40) return null;
  final headerSize = _readU32(dib, 0);
  final width = _readI32(dib, 4);
  final height = _readI32(dib, 8);
  final planes = _readU16(dib, 12);
  final bitCount = _readU16(dib, 14);
  final compression = _readU32(dib, 16);
  if (headerSize < 40 || width <= 0 || height == 0 || planes != 1) return null;
  if (compression != _biRgb && compression != _biBitfields) return null;
  if (bitCount != 24 && bitCount != 32) return null;

  // 通道掩码：BI_RGB 用约定俗成的 BGR(A) 排布；BI_BITFIELDS 读 DIB 里给的
  // 掩码（V4/V5 头在 40..55，40 字节头的掩码紧跟其后）。
  var rMask = 0x00ff0000, gMask = 0x0000ff00, bMask = 0x000000ff;
  var aMask = bitCount == 32 ? 0xff000000 : 0;
  if (compression == _biBitfields) {
    final m = headerSize >= 52 ? 40 : headerSize;
    if (dib.length < m + 12) return null;
    rMask = _readU32(dib, m);
    gMask = _readU32(dib, m + 4);
    bMask = _readU32(dib, m + 8);
    aMask = headerSize >= 56 && dib.length >= m + 16 ? _readU32(dib, m + 12) : 0;
  }

  final topDown = height < 0;
  final h = height.abs();
  final bytesPerRow = ((width * bitCount + 31) ~/ 32) * 4;
  var pixelOffset = headerSize;
  if (compression == _biBitfields && headerSize == 40) pixelOffset += 12;
  if (dib.length < pixelOffset + bytesPerRow * h) return null;

  final bytesPerPixel = bitCount ~/ 8;
  final bgra = Uint8List(width * h * 4);
  for (var y = 0; y < h; y++) {
    final srcY = topDown ? y : h - 1 - y;
    final srcRow = pixelOffset + srcY * bytesPerRow;
    for (var x = 0; x < width; x++) {
      final src = srcRow + x * bytesPerPixel;
      final value = bytesPerPixel == 4
          ? _readU32(dib, src)
          : dib[src] | (dib[src + 1] << 8) | (dib[src + 2] << 16);
      final dst = (y * width + x) * 4;
      bgra[dst] = _channel(value, bMask, 0);
      bgra[dst + 1] = _channel(value, gMask, 0);
      bgra[dst + 2] = _channel(value, rMask, 0);
      bgra[dst + 3] = aMask == 0 ? 255 : _channel(value, aMask, 255);
    }
  }
  return CapturedImage(width: width, height: h, bgra: bgra);
}

/// 按掩码取出一个通道并归一到 0..255（掩码为 0 时用 [fallback]）。
int _channel(int value, int mask, int fallback) {
  if (mask == 0) return fallback;
  var shift = 0;
  while (((mask >> shift) & 1) == 0 && shift < 32) {
    shift++;
  }
  final maxValue = mask >> shift;
  if (maxValue == 0) return fallback;
  final raw = (value & mask) >> shift;
  return ((raw * 255) / maxValue).round().clamp(0, 255);
}

int _readU16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

/// 有符号 32 位。**必须真的做符号扩展**：DIB 的 `biHeight` 为负表示
/// 「自上而下」的行序，不扩展的话 -1 会读成 4294967295，解析直接判成尺寸非法
/// （M14 第 3 条补的用例就是这么发现的）。
int _readI32(Uint8List b, int o) {
  final v = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int _readU32(Uint8List b, int o) => _readI32(b, o) & 0xffffffff;

/// 剪贴板图片（与 CapturedScreen 同构，但带内容去重 hash）。
class CapturedImage {
  final int width;
  final int height;
  final Uint8List bgra;
  late final String contentHash = _hash();

  CapturedImage({required this.width, required this.height, required this.bgra});

  String _hash() {
    var h = 2166136261;
    // 抽样 FNV，足够去重。
    final step = bgra.length ~/ 65536 + 1;
    for (var i = 0; i < bgra.length; i += step) {
      h ^= bgra[i];
      h = (h * 16777619) & 0xffffffff;
    }
    return '${width}x$height-$h';
  }
}
