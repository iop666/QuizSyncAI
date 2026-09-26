import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 归一化裁剪矩形（0..1）。
typedef CropRect = ({double x1, double y1, double x2, double y2});

/// 手动框选重试（SPEC §8）：对**已捕获的截图**在应用内拖一个矩形裁剪后重析。
/// 该入口只在「未识别到题目」时临时启用（用户决策 6：默认关闭、不常驻设置）。
class CropRetryDialog extends StatefulWidget {
  final Uint8List jpegBytes;
  final int imageWidth;
  final int imageHeight;

  const CropRetryDialog({
    super.key,
    required this.jpegBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  State<CropRetryDialog> createState() => _CropRetryDialogState();
}

class _CropRetryDialogState extends State<CropRetryDialog> {
  Rect? _rect;
  Offset? _start;

  /// 图片显示区域的实际尺寸。**不能**用 `context.size`：那返回的是整个
  /// Dialog 的尺寸，用它归一化会让裁剪区域整体偏移（选取下半张却被裁成中间
  /// 一条，且右边永远选不到）。
  Size _imageBox = Size.zero;

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _start = d.localPosition;
      _rect = Rect.fromPoints(_start!, _start!);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_start != null) {
      setState(() {
        _rect = Rect.fromPoints(_start!, d.localPosition);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.imageWidth / widget.imageHeight;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('框选题目区域',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '在图上按住鼠标拖出一个矩形，只把这一块发给 AI。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: LayoutBuilder(builder: (context, constraints) {
                    _imageBox = constraints.biggest;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black12),
                            Image.memory(widget.jpegBytes, fit: BoxFit.fill),
                            // 未框选时给一层暗色，提示「先框一下」。
                            if (_rect == null)
                              Container(color: Colors.black.withValues(alpha: 0.22)),
                            if (_rect != null)
                              Positioned.fromRect(
                                rect: _rect!,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_rect != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _rect = null),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('重选'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('crop-confirm'),
                    onPressed: _rect == null
                        ? null
                        : () {
                            final box = _imageBox;
                            final r = _rect!;
                            if (box.width <= 0 || box.height <= 0) return;
                            // 用图片区域尺寸归一化，并保证左上/右下有序。
                            final left = r.left < r.right ? r.left : r.right;
                            final top = r.top < r.bottom ? r.top : r.bottom;
                            final right = r.left < r.right ? r.right : r.left;
                            final bottom = r.top < r.bottom ? r.bottom : r.top;
                            Navigator.of(context).pop((
                              x1: (left / box.width).clamp(0.0, 1.0),
                              y1: (top / box.height).clamp(0.0, 1.0),
                              x2: (right / box.width).clamp(0.0, 1.0),
                              y2: (bottom / box.height).clamp(0.0, 1.0),
                            ));
                          },
                    icon: const Icon(Icons.crop, size: 18),
                    label: const Text('框选重试'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出框选对话框；返回归一化矩形（null 表示取消）。
Future<CropRect?> showCropRetryDialog(
  BuildContext context, {
  required Uint8List jpegBytes,
  required int imageWidth,
  required int imageHeight,
}) {
  return showDialog<CropRect>(
    context: context,
    builder: (_) => CropRetryDialog(
      jpegBytes: jpegBytes,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    ),
  );
}
