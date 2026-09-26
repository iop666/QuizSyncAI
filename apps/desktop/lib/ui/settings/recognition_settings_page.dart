import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart' show kHardMaxPagesPerTask;
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../state/app_scope.dart';

/// 识别设置（M9）：采集 / 多页识别 / 本地缓存中真正属于「识别」的项。
/// 这里原来散落在「采集」和「多页识别与本地缓存」两张卡片里。
class RecognitionSettingsPage extends ConsumerStatefulWidget {
  const RecognitionSettingsPage({super.key});

  @override
  ConsumerState<RecognitionSettingsPage> createState() =>
      _RecognitionSettingsPageState();
}

class _RecognitionSettingsPageState
    extends ConsumerState<RecognitionSettingsPage> {
  /// 可选的缓存上限档位；0 = 不设限。
  static const _cacheChoices = [30, 60, 120, 0];

  /// 拖动中的临时值：松手才落库。
  int? _multiPageDraft;

  Future<void> _save(AppSettings v) async {
    await ref.read(settingsProvider).updateApp(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = ref.watch(settingsProvider).app;
    final multiPageLimit = _multiPageDraft ?? app.multiPageLimit;
    final selectedCache =
        _cacheChoices.contains(app.imageCacheLimit) ? app.imageCacheLimit : 60;

    return SettingsSection(
      title: '识别设置',
      description: '截图后怎么识别、一次识别多少页、本机保留多少张图。',
      children: [
        SettingsGroup(
          title: '自动识别',
          icon: Icons.bolt_outlined,
          children: [
            SettingsRow(
              key: const ValueKey('settings-clipboard-watch'),
              title: '剪贴板监听',
              subtitle: '检测到新图片后自动分析（Win+Shift+S 截完即出结果）',
              trailing: SettingsSwitch(
                value: app.clipboardWatch,
                onChanged: (v) => _save(app.copyWith(clipboardWatch: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '图片处理',
          icon: Icons.image_outlined,
          children: [
            SettingsRow(
              key: const ValueKey('settings-save-images'),
              title: '保存图片文件到本地',
              subtitle: '关闭后只保留文本结果；重试与框选会不可用',
              trailing: SettingsSwitch(
                value: app.saveImageFiles,
                onChanged: (v) => _save(app.copyWith(saveImageFiles: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '多页识别',
          icon: Icons.layers_outlined,
          description: '一道题要截好几张（题干 + 选项 + 图）时，攒够页数一次上传。',
          children: [
            SettingsField(
              title: '多页识别页数上限',
              subtitle: '抓满上限会自动上传本次全部页面；硬上限 $kHardMaxPagesPerTask 页',
              info: '攒页方式：按「多页模式」热键逐页追加（热键被占用时用托盘菜单），'
                  '抓满上限自动上传识别；没满就按「截屏识别」热键结束多页并一次上传，'
                  'AI 会把跨页的题干与选项合并成同一道题。',
              maxWidth: 520,
              child: Row(
                children: [
                  Text('1', style: SettingsType.aux(scheme)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-multi-page'),
                      value: multiPageLimit.toDouble(),
                      min: 1,
                      max: kHardMaxPagesPerTask.toDouble(),
                      divisions: kHardMaxPagesPerTask - 1,
                      label: '$multiPageLimit 页',
                      onChanged: (v) =>
                          setState(() => _multiPageDraft = v.round()),
                      onChangeEnd: (v) {
                        setState(() => _multiPageDraft = null);
                        _save(app.copyWith(multiPageLimit: v.round()));
                      },
                    ),
                  ),
                  Text('$kHardMaxPagesPerTask', style: SettingsType.aux(scheme)),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '$multiPageLimit 页',
                      key: const ValueKey('settings-multi-page-value'),
                      textAlign: TextAlign.end,
                      style: SettingsType.value(scheme),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '本地图片缓存',
          icon: Icons.folder_open_outlined,
          children: [
            SettingsField(
              title: '本地图片缓存上限',
              subtitle: app.imageCacheLimit == 0
                  ? '当前：不设限（截图会一直留着，占用磁盘会持续增长）'
                  : '当前：最多保留 ${app.imageCacheLimit} 张，'
                      '超出的旧截图在识别完成后自动清理',
              info: '这里只清「本地截图」：数据库里的题目与答案不受影响。'
                  '关掉「保存图片文件到本地」后缓存不再增长。',
              maxWidth: 480,
              child: SegmentedButton<int>(
                key: const ValueKey('settings-image-cache'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 30, label: Text('30 张')),
                  ButtonSegment(value: 60, label: Text('60 张')),
                  ButtonSegment(value: 120, label: Text('120 张')),
                  ButtonSegment(value: 0, label: Text('不设限')),
                ],
                selected: {selectedCache},
                onSelectionChanged: (v) =>
                    _save(app.copyWith(imageCacheLimit: v.first)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
