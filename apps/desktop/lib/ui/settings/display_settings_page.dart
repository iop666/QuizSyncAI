import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../state/app_scope.dart';

/// 显示设置（M9，用户反馈 1/9）：
/// 外观（主题三态 + 界面缩放）、题目显示（字号 + 字重，带实时预览）。
class DisplaySettingsPage extends ConsumerStatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  ConsumerState<DisplaySettingsPage> createState() =>
      _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends ConsumerState<DisplaySettingsPage> {
  /// 拖动中的临时值：松手才落库（原来每移动一格写一次数据库）。
  double? _fontDraft;

  Future<void> _save(AppSettings v) async {
    await ref.read(settingsProvider).updateApp(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = ref.watch(settingsProvider).app;
    final fontSize = _fontDraft ?? app.fontSize;
    final uiScale = app.uiScale;
    final weight = app.questionFontWeight;

    return SettingsSection(
      title: '显示设置',
      description: '界面外观、整体缩放，以及题目正文字号与字重。',
      children: [
        SettingsGroup(
          title: '外观',
          icon: Icons.palette_outlined,
          children: [
            SettingsField(
              title: '主题',
              subtitle: '跟随系统时，随 Windows 的浅色 / 深色设置切换',
              info: '主题只影响本机显示：浅色 / 深色两套配色都按 Fluent 观感调过，'
                  '答案标绿的颜色在两种主题下各有独立色值（深色下更亮）。',
              maxWidth: 420,
              child: SegmentedButton<ThemeMode2>(
                key: const ValueKey('settings-theme'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: ThemeMode2.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode2.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode2.dark, label: Text('深色')),
                ],
                selected: {app.theme},
                onSelectionChanged: (v) => _save(app.copyWith(theme: v.first)),
              ),
            ),
            // 用户反馈 7：界面缩放只给一档一档的下拉框（不再用进度条），
            // 选完立刻生效，并且**自动把窗口边界按比例放大/缩小**，
            // 这样缩放后看得见的界面范围基本不变（窗口大小跟着走）。
            SettingsField(
              key: const ValueKey('settings-ui-scale'),
              title: '界面缩放',
              subtitle: '当前 ${(uiScale * 100).round()}%',
              info: '整个界面（含设置页与弹窗）一起等比缩放，文字仍然清晰。'
                  '选中后窗口大小会自动按同比例调整，缩放前后可见的内容范围基本一致。',
              maxWidth: 320,
              child: DropdownButtonFormField<double>(
                key: const ValueKey('settings-ui-scale-dropdown'),
                initialValue: nearestUiScalePreset(uiScale),
                decoration: const InputDecoration(),
                items: [
                  for (final p in kUiScalePresets)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${(p * 100).round()}%'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _save(app.copyWith(uiScale: v));
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '题目显示',
          icon: Icons.text_fields,
          description: '题干、选项、答案与解析的正文字号与字重。',
          children: [
            SettingsField(
              key: const ValueKey('settings-font-size'),
              title: '题目字号',
              subtitle: '当前 ${fontSize.round()}',
              info: '题干与选项的字号；在主界面按 Ctrl + 滚轮也能实时调整。',
              maxWidth: 520,
              child: Row(
                children: [
                  Text('小', style: SettingsType.aux(scheme)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-font-size-slider'),
                      value: fontSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      label: fontSize.round().toString(),
                      onChanged: (v) => setState(() => _fontDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _fontDraft = null);
                        _save(app.copyWith(fontSize: v));
                      },
                    ),
                  ),
                  Text('大', style: SettingsType.aux(scheme)),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${fontSize.round()}',
                      key: const ValueKey('settings-font-size-value'),
                      textAlign: TextAlign.end,
                      style: SettingsType.value(scheme),
                    ),
                  ),
                ],
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-question-weight'),
              title: '题目字重',
              subtitle: '当前 ${_weightName(weight)}（$weight）',
              info: '界面字体是 MiSans 可变字体，字重直接走字体的 wght 轴；'
                  '变细适合看长题干，变粗适合投影或截图后放大看。',
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('细', style: SettingsType.aux(scheme)),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('settings-question-weight-slider'),
                          value: weight.toDouble(),
                          min: 300,
                          max: 700,
                          divisions: 4,
                          label: _weightName(weight),
                          onChanged: (v) => _save(
                              app.copyWith(questionFontWeight: v.round())),
                        ),
                      ),
                      Text('粗', style: SettingsType.aux(scheme)),
                      SizedBox(
                        width: 56,
                        child: Text(
                          _weightName(weight),
                          key: const ValueKey('settings-question-weight-value'),
                          textAlign: TextAlign.end,
                          style: SettingsType.value(scheme),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SettingsGap.s8),
                  // 实时预览：改字重/字号立刻能看出差别，不用回去看题目。
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(SettingsGap.s16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                          color: QuizSyncTheme.outline(theme.brightness)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('预览', style: SettingsType.aux(scheme)),
                        const SizedBox(height: SettingsGap.s8),
                        Text(
                          '3. 第 12 题  下列关于函数的说法正确的是（　）',
                          key: const ValueKey('settings-question-preview'),
                          style: questionWeightStyle(weight,
                              base: TextStyle(
                                  fontSize: fontSize,
                                  height: 1.6,
                                  color: scheme.onSurface)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _weightName(int weight) => switch (weight) {
        <= 300 => '细',
        <= 400 => '常规',
        <= 500 => '中等',
        <= 600 => '半粗',
        _ => '粗',
      };
}
