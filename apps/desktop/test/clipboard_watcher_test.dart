import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

import 'package:quizsync_desktop/services/clipboard_watcher.dart';

/// M14 第 3 条（用户反馈：「剪切板监听毫无作用」）。
///
/// **根因是实测出来的**：本机用 `Clipboard.SetImage` 放一张真图后枚举剪贴板，
/// CF_DIB 存在、`GlobalLock` 成功、`GlobalSize` 也够，但它的
/// `biCompression = 3 = BI_BITFIELDS`（现代截图工具 / 浏览器 / .NET 都这么放图），
/// 而旧解析只认 `BI_RGB` —— 每一步都成功，最后静默返回 null，
/// 于是监听器「毫无作用」。
///
/// 下面分两层锁住：① 直接喂构造出来的 DIB（含 BI_BITFIELDS 两种头形态）；
/// ② 真的往系统剪贴板里放一张图，走一遍读取与监听回调。
void main() {
  /// 构造一张 32bpp DIB。[headerSize] 40 = V3 头（BI_BITFIELDS 的掩码跟在头后），
  /// 124 = V5 头（掩码在头内部）。像素按「从下到上」的行序写入（DIB 默认）。
  Uint8List buildDib({
    required int width,
    required int height,
    required int compression,
    required List<int> bgraRows,
    int headerSize = 40,
    bool topDown = false,
    int rMask = 0x00ff0000,
    int gMask = 0x0000ff00,
    int bMask = 0x000000ff,
    int aMask = 0xff000000,
  }) {
    final bytesPerRow = ((width * 32 + 31) ~/ 32) * 4;
    final maskBytes = headerSize == 40 && compression == 3 ? 12 : 0;
    final total = headerSize + maskBytes + bytesPerRow * height;
    final dib = Uint8List(total);
    void u16(int o, int v) {
      dib[o] = v & 0xff;
      dib[o + 1] = (v >> 8) & 0xff;
    }

    void u32(int o, int v) {
      dib[o] = v & 0xff;
      dib[o + 1] = (v >> 8) & 0xff;
      dib[o + 2] = (v >> 16) & 0xff;
      dib[o + 3] = (v >> 24) & 0xff;
    }

    u32(0, headerSize);
    u32(4, width);
    u32(8, topDown ? -height : height);
    u16(12, 1);
    u16(14, 32);
    u32(16, compression);
    u32(20, bytesPerRow * height);
    if (headerSize >= 124) {
      // BITMAPV4/V5 的掩码位置固定：40/44/48/52。
      u32(40, rMask);
      u32(44, gMask);
      u32(48, bMask);
      u32(52, aMask);
    } else if (compression == 3) {
      u32(40, rMask);
      u32(44, gMask);
      u32(48, bMask);
    }
    final pixelOffset = headerSize + maskBytes;
    for (var i = 0; i < height; i++) {
      final row = i * bytesPerRow;
      for (var x = 0; x < width; x++) {
        final v = bgraRows[i * width + x];
        u32(pixelOffset + row + x * 4, v);
      }
    }
    return dib;
  }

  /// 32bpp 像素值：按「B 在最低字节」的常见排布打包。
  int pixel(int b, int g, int r, [int a = 0xff]) =>
      (a << 24) | (r << 16) | (g << 8) | b;

  group('解析 DIB 字节', () {
    test('BI_RGB 32bpp：BGR(A) 原样取出', () {
      // 两行：上行黑/白，下行红/绿（DIB 行序自下而上，解析要翻回来）。
      final dib = buildDib(
        width: 2,
        height: 2,
        compression: 0,
        bgraRows: [
          pixel(0, 0, 255), // 红（底行）
          pixel(0, 255, 0), // 绿
          pixel(0, 0, 0), // 黑（顶行）
          pixel(255, 255, 255), // 白
        ],
      );
      final img = parseClipboardDib(dib)!;
      expect(img.width, 2);
      expect(img.height, 2);
      // 解析结果按「从上到下」存放：第一行 = 原 DIB 的最后一行。
      expect(img.bgra.sublist(0, 4), [0, 0, 0, 255], reason: '左上 = 黑');
      expect(img.bgra.sublist(4, 8), [255, 255, 255, 255], reason: '右上 = 白');
      expect(img.bgra.sublist(8, 12), [0, 0, 255, 255], reason: '左下 = 红');
      expect(img.bgra.sublist(12, 16), [0, 255, 0, 255], reason: '右下 = 绿');
    });

    test('BI_BITFIELDS（40 字节头，掩码紧跟头后）：必须能解析', () {
      // 这就是本机实测到的真实剪贴板形态（headerSize=40, comp=3, 32bpp）。
      final dib = buildDib(
        width: 3,
        height: 1,
        compression: 3,
        bgraRows: [pixel(255, 0, 0), pixel(0, 255, 0), pixel(0, 0, 255)],
      );
      final img = parseClipboardDib(dib);
      expect(img, isNotNull, reason: '旧代码只认 BI_RGB，这里必然 null——用户说「毫无作用」就是它');
      expect(img!.bgra.sublist(0, 4), [255, 0, 0, 255], reason: '蓝');
      expect(img.bgra.sublist(4, 8), [0, 255, 0, 255], reason: '绿');
      expect(img.bgra.sublist(8, 12), [0, 0, 255, 255], reason: '红');
      expect([img.bgra[3], img.bgra[7], img.bgra[11]], [255, 255, 255],
          reason: '40 字节头没有 alpha 掩码：必须当成不透明，否则整张图会变全透明/全黑');
    });

    test('BI_BITFIELDS（V5 头，掩码在头内）+ 非默认掩码顺序也能正确取通道', () {
      final dib = buildDib(
        width: 1,
        height: 1,
        compression: 3,
        headerSize: 124,
        // 故意换成 RGBA 排布：R 在最低字节。
        rMask: 0x000000ff,
        gMask: 0x0000ff00,
        bMask: 0x00ff0000,
        aMask: 0xff000000,
        bgraRows: [(0xff << 24) | (0x11 << 16) | (0x22 << 8) | 0x33],
      );
      final img = parseClipboardDib(dib)!;
      expect(img.bgra.sublist(0, 4), [0x11, 0x22, 0x33, 0xff],
          reason: '按掩码映射（B=0x11 G=0x22 R=0x33），不能写死 BGR 顺序');
    });

    test('自下而上 / 自上而下两种行序都能解析', () {
      final bottomUp = buildDib(
        width: 1,
        height: 2,
        compression: 0,
        bgraRows: [pixel(1, 1, 1), pixel(2, 2, 2)],
      );
      final topDown = buildDib(
        width: 1,
        height: 2,
        compression: 0,
        topDown: true,
        bgraRows: [pixel(1, 1, 1), pixel(2, 2, 2)],
      );
      expect(parseClipboardDib(bottomUp)!.bgra[0], 2, reason: '底行在上时，顶行是最后写入的那行');
      expect(parseClipboardDib(topDown)!.bgra[0], 1, reason: '自上而下时保持原序');
    });

    test('垃圾数据 / 截断数据一律返回 null（不崩、不越界读）', () {
      expect(parseClipboardDib(Uint8List(0)), isNull);
      expect(parseClipboardDib(Uint8List(39)), isNull);
      final ok = buildDib(
          width: 4, height: 4, compression: 3, bgraRows: List.filled(16, pixel(9, 9, 9)));
      expect(parseClipboardDib(ok.sublist(0, ok.length - 100)), isNull,
          reason: '尺寸不够时不能硬读');
    });
  });

  group('真实系统剪贴板（会改动本机剪贴板内容）', () {
    late int seqBefore;

    tearDown(() {
      // 尽量把剪贴板留空，别留一张 3×1 的测试图给用户。
      if (OpenClipboard(0) != 0) {
        try {
          EmptyClipboard();
        } finally {
          CloseClipboard();
        }
      }
    });

    /// 把 DIB 放进系统剪贴板（`SetClipboardData` 之后内存归系统所有，不要 free）。
    bool putDib(Uint8List dib) {
      if (OpenClipboard(0) == 0) return false;
      try {
        if (EmptyClipboard() == 0) return false;
        final hMem = GlobalAlloc(GMEM_MOVEABLE, dib.length);
        if (hMem == nullptr) return false;
        final ptr = GlobalLock(hMem);
        if (ptr == nullptr) return false;
        ptr.cast<Uint8>().asTypedList(dib.length).setAll(0, dib);
        GlobalUnlock(hMem);
        return SetClipboardData(CF_DIB, hMem.address) != 0;
      } finally {
        CloseClipboard();
      }
    }

    /// 等到 [done] 成立（最多 [timeout]）。
    ///
    /// 这条用例动的是**真实系统剪贴板**，原来靠「睡 250/300 ms 再看结果」——
    /// 本机并行跑别的重测试文件时（实测 `float_window_compose_test` 一起跑），
    /// 40 ms 的轮询会被 CPU 挤晚，于是**假红**（单独跑 / `--concurrency=1` 全绿）。
    /// 改成有上限的等待：断言还是「监听器必须回调」，只是不再和墙钟较劲。
    Future<void> waitFor(bool Function() done,
        {Duration timeout = const Duration(seconds: 5)}) async {
      final deadline = DateTime.now().add(timeout);
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('读取函数能拿到刚放进剪贴板的图，且监听器会回调', () async {
      seqBefore = GetClipboardSequenceNumber();
      final dib = buildDib(
        width: 3,
        height: 1,
        compression: 3,
        bgraRows: [pixel(255, 0, 0), pixel(0, 255, 0), pixel(0, 0, 255)],
      );
      if (!putDib(dib)) {
        // M47：剪贴板被别的进程占着（本机实测：小米云服务会短暂锁剪贴板）时，
        // 原来这里直接 `return` —— 于是**含 M14 回归点在内**的整段断言一次都不
        // 跑，而退出码仍然是 0（假绿）。现在只跳过「真剪贴板往返」这一半，
        // 解码这条回归点照跑：M14 的根因就是 BI_BITFIELDS 解不出来。
        final decoded = parseClipboardDib(dib);
        expect(decoded, isNotNull,
            reason: 'M14 第 3 条的回归点：BI_BITFIELDS 的 DIB 必须能解出来');
        expect(decoded!.width, 3);
        expect(decoded.height, 1);
        markTestSkipped('剪贴板被其他进程占用：跳过「真剪贴板」往返，解码断言已照跑');
        return;
      }

      final direct = readClipboardImageNow();
      expect(direct, isNotNull, reason: 'M14 第 3 条的回归点');
      expect(direct!.width, 3);
      expect(direct.height, 1);

      final fired = <CapturedImage>[];
      final watcher = ClipboardWatcher(
          onImage: fired.add, interval: const Duration(milliseconds: 40));
      watcher.start();
      addTearDown(watcher.stop);

      // 第一次：剪贴板里已经是一张「新」图（序列号与上次不同），应当触发。
      await waitFor(() => fired.isNotEmpty);
      expect(fired, isNotEmpty, reason: '监听器必须真的回调，否则就是「毫无作用」');
      expect(fired.last.width, 3);

      // 换一张不同尺寸的图 → 再触发一次。
      final before = fired.length;
      expect(
          putDib(buildDib(
              width: 5,
              height: 2,
              compression: 3,
              bgraRows: List.filled(10, pixel(7, 7, 7)))),
          isTrue);
      await waitFor(() => fired.length > before);
      expect(fired.length, greaterThan(before));
      expect(fired.last.width, 5);

      // 同一张图再放一次 → 内容 hash 相同，不重复触发（避免反复烧 AI 额度）。
      final afterSecond = fired.length;
      expect(
          putDib(buildDib(
              width: 5,
              height: 2,
              compression: 3,
              bgraRows: List.filled(10, pixel(7, 7, 7)))),
          isTrue);
      // 「不该再触发」是**否定**断言：必须给它足够时间才判得准。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fired.length, afterSecond, reason: '内容没变就不该再触发');
      expect(seqBefore, isNotNull);
    });
  });
}
