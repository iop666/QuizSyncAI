import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show
        kDefaultBallOpacity,
        kDefaultBallSize,
        kDefaultBallStrokeOpacity,
        kMaxBallSize,
        kMaxBallStrokeWidth,
        kMinBallOpacity,
        kMinBallSize;
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/floating_ball.dart' show BallState;
import '../../state/app_scope.dart';

/// 悬浮球设置（用户反馈 11）：开关 → 大小 / 透明度 → 描边（开关 / 宽度 /
/// 透明度，颜色跟随悬浮球当前状态的主色）。
///
/// 交互与安卓端一致：单击 = 截一张图直接识别（多页攒页时 = 收尾识别），
/// **左键长按 500ms 或右键**（两者完全等价）= 追加一页进入多页模式；
/// 拖动后自动吸附左右边缘。
///
/// 描边是**向外**画的一圈（用户反馈 M16 第 1 条）：颜色取状态主色并加深，
/// 见 `services/ball_paint.dart`。
class BallSettingsPage extends ConsumerStatefulWidget {
  const BallSettingsPage({super.key});

  @override
  ConsumerState<BallSettingsPage> createState() => _BallSettingsPageState();
}

class _BallSettingsPageState extends ConsumerState<BallSettingsPage> {
  /// 拖动中的草稿值：松手才落库（避免每帧都写数据库 + 重画悬浮球）。
  double? _sizeDraft;
  double? _opacityDraft;
  double? _strokeWidthDraft;
  double? _strokeOpacityDraft;

  Future<void> _save(AppSettings v) async {
    await ref.read(settingsProvider).updateApp(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = ref.watch(settingsProvider).app;
    final size = _sizeDraft ?? app.ballSize;
    final opacity = _opacityDraft ?? app.ballOpacity;
    final strokeWidth = _strokeWidthDraft ?? app.ballStrokeWidth;
    final strokeOpacity = _strokeOpacityDraft ?? app.ballStrokeOpacity;

    return SettingsSection(
      title: '悬浮球设置',
      description: '桌面上的圆形悬浮球：随时单击截屏识别，不用切回主窗口。'
          '点击逻辑与手机端一致。',
      children: [
        SettingsGroup(
          title: '悬浮球',
          icon: Icons.bubble_chart_outlined,
          children: [
            SettingsRow(
              key: const ValueKey('settings-ball-switch'),
              title: '显示悬浮球',
              subtitle: '置顶在所有窗口之上；单击识别，左键长按 / 右键追加一页',
              info: '悬浮球是一个独立的原生分层窗口：拖动后可停靠到屏幕左/右边缘，'
                  '位置会记住到本次运行结束；截屏前会自动隐藏，不会出现在识别结果里。',
              trailing: SettingsSwitch(
                value: app.ballEnabled,
                onChanged: (v) => _save(app.copyWith(ballEnabled: v)),
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-ball-size'),
              title: '大小',
              subtitle: '当前 ${size.round()}（逻辑像素，范围 '
                  '${kMinBallSize.round()}–${kMaxBallSize.round()}）',
              maxWidth: 520,
              child: Row(
                children: [
                  Text('小', style: SettingsType.aux(scheme)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-ball-size-slider'),
                      value: size,
                      min: kMinBallSize,
                      max: kMaxBallSize,
                      divisions: (kMaxBallSize - kMinBallSize) ~/ 4,
                      label: '${size.round()}',
                      onChanged: (v) => setState(() => _sizeDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _sizeDraft = null);
                        _save(app.copyWith(ballSize: v));
                      },
                    ),
                  ),
                  Text('大', style: SettingsType.aux(scheme)),
                  SizedBox(
                    width: 40,
                    child: Text('${size.round()}',
                        key: const ValueKey('settings-ball-size-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-ball-opacity'),
              title: '透明度',
              subtitle: '当前 ${(opacity * 100).round()}%',
              info: '默认 ${(kDefaultBallOpacity * 100).round()}%：既能看清悬浮球，'
                  '又不会挡住下面的内容。最低 ${(kMinBallOpacity * 100).round()}%。',
              maxWidth: 520,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-ball-opacity-slider'),
                      value: opacity,
                      min: kMinBallOpacity,
                      max: 1,
                      divisions: 16,
                      label: '${(opacity * 100).round()}%',
                      onChanged: (v) => setState(() => _opacityDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _opacityDraft = null);
                        _save(app.copyWith(ballOpacity: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('${(opacity * 100).round()}%',
                        key: const ValueKey('settings-ball-opacity-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '描边',
          icon: Icons.circle_outlined,
          description: '给悬浮球加一圈边，画在球的「外面」并且垫在球的**下面**'
              '（不会盖住球本身）；颜色跟随当前状态的主色并加深一些'
              '（待识别=蓝 / 识别中=黄 / 多页模式=绿）。'
              '球不是标准圆形，环带会往球内多重叠一点把缝隙填上。',
          children: [
            SettingsRow(
              key: const ValueKey('settings-ball-stroke-switch'),
              title: '开启描边',
              subtitle: app.ballStroke ? '已开启（默认开启）' : '已关闭',
              info: '默认开启：宽 4、不透明度 25%，颜色取当前状态主色并加深。'
                  '描边画在球的下面、比球的外缘再往外一点，'
                  '所以球看起来大小不变，只是多了一圈更深的边。',
              trailing: SettingsSwitch(
                value: app.ballStroke,
                onChanged: (v) => _save(app.copyWith(ballStroke: v)),
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-ball-stroke-width'),
              title: '描边宽度',
              subtitle: '当前 ${strokeWidth.toStringAsFixed(1)}'
                  '（0–${kMaxBallStrokeWidth.round()}）',
              maxWidth: 520,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-ball-stroke-width-slider'),
                      value: strokeWidth,
                      min: 0,
                      max: kMaxBallStrokeWidth,
                      divisions: kMaxBallStrokeWidth.round() * 2,
                      label: strokeWidth.toStringAsFixed(1),
                      onChanged: app.ballStroke
                          ? (v) => setState(() => _strokeWidthDraft = v)
                          : null,
                      onChangeEnd: (v) {
                        setState(() => _strokeWidthDraft = null);
                        _save(app.copyWith(ballStrokeWidth: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(strokeWidth.toStringAsFixed(1),
                        key: const ValueKey('settings-ball-stroke-width-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-ball-stroke-opacity'),
              title: '描边透明度',
              subtitle: '当前 ${(strokeOpacity * 100).round()}%'
                  '（默认 ${(kDefaultBallStrokeOpacity * 100).round()}%）',
              maxWidth: 520,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-ball-stroke-opacity-slider'),
                      value: strokeOpacity,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      label: '${(strokeOpacity * 100).round()}%',
                      onChanged: app.ballStroke
                          ? (v) => setState(() => _strokeOpacityDraft = v)
                          : null,
                      onChangeEnd: (v) {
                        setState(() => _strokeOpacityDraft = null);
                        _save(app.copyWith(ballStrokeOpacity: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('${(strokeOpacity * 100).round()}%',
                        key: const ValueKey('settings-ball-stroke-opacity-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '状态与主色',
          icon: Icons.palette_outlined,
          children: [
            for (final s in BallState.values)
              SettingsRow(
                key: ValueKey('settings-ball-state-${s.name}'),
                title: s.label,
                subtitle: switch (s) {
                  BallState.idle => '空闲：单击截屏识别，左键长按 / 右键追加一页',
                  BallState.detecting => '正在识别上一张：此时点击只会提示稍候',
                  BallState.multiPage => '已开始攒页：单击收尾识别本次全部页面',
                },
                trailing: SettingsStatusDot(color: Color(s.mainColor)),
              ),
          ],
        ),
        SettingsNote(
          text: '默认大小 ${kDefaultBallSize.round()}、透明度 '
              '${(kDefaultBallOpacity * 100).round()}%。悬浮球与热键互不影响：'
              '两者都可以触发识别，热键设置页里暂停的是全局热键。',
        ),
      ],
    );
  }
}
