import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/ui/crop_retry_dialog.dart';

/// 框选重试的回归测试：归一化必须基于**图片显示区域**的尺寸。
/// 原来用的是 `context.size`（整个 Dialog 的尺寸），于是用户框选下半张图，
/// 实际裁出来的是中间一条（reviewer 已复现：整张图拖动得到 696/800）。
void main() {
  testWidgets('整张图拖动 → 归一化矩形应为 (0,0,1,1)', (tester) async {
    final jpeg = Uint8List.fromList(_tinyJpeg);
    CropRect? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCropRetryDialog(
                  context,
                  jpegBytes: jpeg,
                  imageWidth: 800,
                  imageHeight: 400,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 图片区域的真实尺寸（AspectRatio 的盒子）。
    final box = tester.getRect(find.byType(AspectRatio));
    expect(box.width, greaterThan(0));
    // Dialog 比图片区域宽/高，才能暴露用 context.size 归一化的错误。
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.width, greaterThan(box.width));
    expect(dialog.height, greaterThan(box.height),
        reason: 'Dialog 明显高于图片区域，用 context.size 归一化必然偏小');

    // 从图片左上角拖到右下角 = 选中整张图。
    final gesture = await tester.startGesture(box.topLeft + const Offset(0.5, 0.5));
    await tester.pump();
    await gesture.moveTo(box.bottomRight - const Offset(0.5, 0.5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('crop-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.x1, closeTo(0.0, 0.02));
    expect(result!.y1, closeTo(0.0, 0.02));
    expect(result!.x2, closeTo(1.0, 0.02), reason: '右边缘必须可达');
    expect(result!.y2, closeTo(1.0, 0.02), reason: '下边缘必须可达');
  });

  testWidgets('反向拖动（右下 → 左上）也归一化为有序矩形', (tester) async {
    final jpeg = Uint8List.fromList(_tinyJpeg);
    CropRect? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCropRetryDialog(
                  context,
                  jpegBytes: jpeg,
                  imageWidth: 800,
                  imageHeight: 400,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(AspectRatio));
    final gesture = await tester.startGesture(box.bottomRight - const Offset(2, 2));
    await tester.pump();
    await gesture.moveTo(box.topLeft + const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('crop-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.x1, lessThanOrEqualTo(result!.x2));
    expect(result!.y1, lessThanOrEqualTo(result!.y2));
    expect(result!.x2, closeTo(1.0, 0.02));
    expect(result!.y2, closeTo(1.0, 0.02));
  });
}

/// 1x1 的最小 JPEG（够 Image.memory 解码即可）。
const _tinyJpeg = <int>[
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46,
  0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00,
  0xff, 0xdb, 0x00, 0x43, 0x00, 0x03, 0x02, 0x02, 0x02, 0x02,
  0x02, 0x03, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04,
  0x06, 0x04, 0x04, 0x04, 0x04, 0x04, 0x08, 0x06, 0x06, 0x05,
  0x06, 0x09, 0x08, 0x0a, 0x0a, 0x09, 0x08, 0x09, 0x09, 0x0a,
  0x0c, 0x0f, 0x0c, 0x0a, 0x0b, 0x0e, 0x0b, 0x09, 0x09, 0x0d,
  0x11, 0x0d, 0x0e, 0x0f, 0x10, 0x10, 0x11, 0x10, 0x0a, 0x0c,
  0x12, 0x13, 0x12, 0x10, 0x13, 0x0f, 0x10, 0x10, 0x10, 0xff,
  0xc9, 0x00, 0x0b, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01,
  0x11, 0x00, 0xff, 0xcc, 0x00, 0x06, 0x00, 0x10, 0x10, 0x05,
  0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
  0xd2, 0xcf, 0x20, 0xff, 0xd9,
];
