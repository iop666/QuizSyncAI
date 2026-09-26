import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show
        FloatWindowAspect,
        FloatWindowPaletteSpec,
        kDefaultFloatWindowOpacity,
        kDefaultFloatWindowPalette,
        kFloatWindowAspects,
        kFloatWindowDarkPalettes,
        kFloatWindowDefaultMarginX,
        kFloatWindowNoPosition,
        kFloatWindowPalettes,
        kMaxFloatWindowFontScale,
        kMaxFloatWindowScale,
        kMinFloatWindowFontScale,
        kMinFloatWindowOpacity,
        kMinFloatWindowScale,
        floatWindowAspectOf,
        floatWindowPaletteOf;
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../state/app_scope.dart';

/// 悬浮窗设置。
///
/// 变化（M34）：
/// - 顶部只留图标按钮（下一条 / 上一条 / 重新识别 / 极简 / 锁定），
///   **删掉窗内字号按钮**，字号只在这里调；
/// - 标题栏不再显示「共 N 题 / N 张图片」；
/// - 底部两个识别按钮保持**适度尺寸**的整条按钮；
/// - 内容改为**文本为主 + 明显的题目轮廓**（原来离屏渲染整张卡片，悬浮窗很卡）。
class FloatWindowSettingsPage extends ConsumerStatefulWidget {
  const FloatWindowSettingsPage({super.key});

  @override
  ConsumerState<FloatWindowSettingsPage> createState() =>
      _FloatWindowSettingsPageState();
}

class _FloatWindowSettingsPageState
    extends ConsumerState<FloatWindowSettingsPage> {
  double? _opacityDraft;
  double? _scaleDraft;
  double? _fontDraft;

  Future<void> _save(AppSettings v) async {
    await ref.read(settingsProvider).updateApp(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = ref.watch(settingsProvider).app;
    final opacity = _opacityDraft ?? app.floatWindowOpacity;
    final scale = _scaleDraft ?? app.floatWindowScale;
    final font = _fontDraft ?? app.floatWindowFontScale;
    final aspect = floatWindowAspectOf(app.floatWindowAspect);
    final w = aspect.widthAt(scale).round();
    final h = aspect.heightAt(scale).round();

    return SettingsSection(
      title: '悬浮窗设置',
      description: '桌面上的识别结果小窗：不用切回主窗口，就能看答案、'
          '接着识别、翻上一条/下一条。默认**关闭**，打开后会记住状态。'
          '默认显示**默认模式**（只看题目与答案，纯文本、可拖选复制）；'
          '需要解析与阅读材料时切到「详细解析模式」（与主界面同一套题目卡片）。'
          '⚠ **悬浮窗不支持显示公式**：数学/物理公式会按 LaTeX 源码原样显示'
          '（例如 \$x^2-1\$ 会原样画出来），需要看排版好的公式请回主窗口。',
      children: [
        SettingsGroup(
          title: '悬浮窗',
          icon: Icons.select_all,
          children: [
            SettingsRow(
              key: const ValueKey('settings-float-switch'),
              title: '显示悬浮窗',
              subtitle: '默认关闭；打开后按下面的外观显示，并记住开关状态',
              info: '悬浮窗是独立的原生分层窗口（和悬浮球同一套实现，不会为它再起一个 '
                  'Flutter 引擎）。它贴在所有窗口之上，点它上面的按钮**不会抢焦点**。'
                  '默认位置是屏幕右侧、不贴边；**只有顶部第一栏可以拖动**窗口。',
              trailing: SettingsSwitch(
                value: app.floatWindowEnabled,
                onChanged: (v) => _save(app.copyWith(floatWindowEnabled: v)),
              ),
            ),
            SettingsRow(
              key: const ValueKey('settings-float-topmost'),
              title: '置顶显示',
              subtitle:
                  app.floatWindowTopmost ? '已置顶（默认）' : '不置顶，会被其他窗口盖住',
              trailing: SettingsSwitch(
                value: app.floatWindowTopmost,
                onChanged: (v) => _save(app.copyWith(floatWindowTopmost: v)),
              ),
            ),
            SettingsRow(
              key: const ValueKey('settings-float-lock'),
              title: '锁定位置',
              subtitle: app.floatWindowLocked
                  ? '已锁定：拖不动（窗内「锁定位置」按钮也能切换）'
                  : '未锁定：按住**顶部第一栏**即可拖动',
              info: '只有顶部第一栏能拖窗口（窗口内容区要用来滚动与点选，'
                  '整窗可拖会误触）。锁定后拖动被忽略，按钮点击始终有效。',
              trailing: SettingsSwitch(
                value: app.floatWindowLocked,
                onChanged: (v) => _save(app.copyWith(floatWindowLocked: v)),
              ),
            ),
            SettingsRow(
              key: const ValueKey('settings-float-home'),
              title: '归位',
              subtitle: '恢复默认位置：屏幕右侧、距右边缘 '
                  '${kFloatWindowDefaultMarginX.round()}',
              trailing: OutlinedButton(
                key: const ValueKey('settings-float-home-button'),
                onPressed: () => _save(app.copyWith(
                    floatWindowX: kFloatWindowNoPosition,
                    floatWindowY: kFloatWindowNoPosition)),
                child: const Text('恢复默认位置'),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '外观',
          icon: Icons.aspect_ratio,
          description: '**不支持自由拉伸**，只在下面三种外观里选；'
              '每种外观都能用下面的「显示比例」整体放大缩小。',
          children: [
            for (final a in kFloatWindowAspects)
              _aspectRow(a, app, scale),
            SettingsField(
              key: const ValueKey('settings-float-scale'),
              title: '显示比例',
              subtitle: '当前 ${(scale * 100).round()}%，窗口约 $w×$h 逻辑像素'
                  '（${aspect.ratioLabel}）',
              info: '无极调节：${(kMinFloatWindowScale * 100).round()}%–'
                  '${(kMaxFloatWindowScale * 100).round()}%。'
                  '窗口宽度 = 该外观的基准宽度 × 比例，高度由宽高比决定。',
              maxWidth: 520,
              child: Row(
                children: [
                  Text('小', style: SettingsType.aux(scheme)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-float-scale-slider'),
                      value: scale,
                      min: kMinFloatWindowScale,
                      max: kMaxFloatWindowScale,
                      divisions:
                          ((kMaxFloatWindowScale - kMinFloatWindowScale) * 20)
                              .round(),
                      label: '${(scale * 100).round()}%',
                      onChanged: (v) => setState(() => _scaleDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _scaleDraft = null);
                        _save(app.copyWith(floatWindowScale: v));
                      },
                    ),
                  ),
                  Text('大', style: SettingsType.aux(scheme)),
                  SizedBox(
                    width: 52,
                    child: Text('${(scale * 100).round()}%',
                        key: const ValueKey('settings-float-scale-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-float-font'),
              title: '窗内字符大小',
              subtitle: '当前 ${(font * 100).round()}%'
                  '（${(kMinFloatWindowFontScale * 100).round()}%–'
                  '${(kMaxFloatWindowFontScale * 100).round()}%，'
                  '**只能在这里调**：窗内不再有字号按钮）',
              maxWidth: 520,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-float-font-slider'),
                      value: font,
                      min: kMinFloatWindowFontScale,
                      max: kMaxFloatWindowFontScale,
                      divisions: 14,
                      label: '${(font * 100).round()}%',
                      onChanged: (v) => setState(() => _fontDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _fontDraft = null);
                        _save(app.copyWith(floatWindowFontScale: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('${(font * 100).round()}%',
                        key: const ValueKey('settings-float-font-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '配色与模式',
          icon: Icons.palette_outlined,
          description: '悬浮窗自带 6 套配色，**默认是浅色系**。'
              '题目卡片里的标绿/标黄仍按契约走（那是信息，不是装饰）。',
          children: [
            SettingsField(
              key: const ValueKey('settings-float-palette'),
              title: '配色',
              subtitle: '当前：${floatWindowPaletteOf(app.floatWindowPalette).label}'
                  '${app.floatWindowPalette == kDefaultFloatWindowPalette ? '（默认）' : ''}'
                  '${kFloatWindowDarkPalettes.contains(app.floatWindowPalette) ? ' · 已配深色模式' : ''}',
              info: '选「纯净白」「紫罗兰」这两套时会**同时切到深色模式**：'
                  '它们在浅色下正文与底色太接近，看不清。',
              maxWidth: 620,
              child: Wrap(
                spacing: SettingsGap.s8,
                runSpacing: SettingsGap.s8,
                children: [
                  for (final p in kFloatWindowPalettes)
                    _paletteChip(p, app, theme.brightness),
                ],
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-float-theme'),
              title: '明暗模式',
              subtitle: '默认跟随软件设置，也可以单独指定',
              maxWidth: 460,
              child: SegmentedButton<FloatWindowTheme>(
                key: const ValueKey('settings-float-theme-segments'),
                showSelectedIcon: false,
                segments: [
                  for (final t in FloatWindowTheme.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {app.floatWindowTheme},
                onSelectionChanged: (s) =>
                    _save(app.copyWith(floatWindowTheme: s.first)),
              ),
            ),
            SettingsRow(
              key: const ValueKey('settings-float-minimal'),
              title: '详细解析模式',
              subtitle: app.floatWindowMinimal
                  ? '已关闭（默认模式）：只看题目与答案，一题一段纯文本，可以直接拖选复制'
                  : '已开启：和主界面一样列出全部选项、解析与阅读材料',
              info: '默认模式（极简）：只显示题号、题干、选项与答案，**纯文本**，'
                  '可以直接用鼠标拖选字符、右键复制；底部还有一个「复制识别内容」，'
                  '一点就把这一次识别的完整内容复制走。'
                  '详细解析模式：和主界面一样把全部选项、解析、阅读材料都列出来'
                  '（内容多、要滚动，也不能拖选）。'
                  '**两种模式都不排版公式**：悬浮窗是自绘的纯文本面板，公式会以 '
                  'LaTeX 源码显示，公式要看渲染效果请回主窗口（M46 第 2 条如实声明）。',
              trailing: SettingsSwitch(
                value: !app.floatWindowMinimal,
                onChanged: (v) => _save(app.copyWith(floatWindowMinimal: !v)),
              ),
            ),
            SettingsField(
              key: const ValueKey('settings-float-opacity'),
              title: '透明度',
              subtitle: '当前 ${(opacity * 100).round()}%'
                  '（默认 ${(kDefaultFloatWindowOpacity * 100).round()}%，'
                  '最低 ${(kMinFloatWindowOpacity * 100).round()}%）',
              maxWidth: 520,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('settings-float-opacity-slider'),
                      value: opacity,
                      min: kMinFloatWindowOpacity,
                      max: 1,
                      divisions: 16,
                      label: '${(opacity * 100).round()}%',
                      onChanged: (v) => setState(() => _opacityDraft = v),
                      onChangeEnd: (v) {
                        setState(() => _opacityDraft = null);
                        _save(app.copyWith(floatWindowOpacity: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('${(opacity * 100).round()}%',
                        key: const ValueKey('settings-float-opacity-value'),
                        textAlign: TextAlign.end,
                        style: SettingsType.value(scheme)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SettingsNote(
          text: '顶部第一栏：左边是「第几次识别 / 时间」，右边一排**图标按钮**'
              '（鼠标悬停会显示名称），顺序是 下一条 · 上一条 · 重新识别 · '
              '默认模式 · 锁定位置。底部是「识别一张」「多页识别」两个按钮'
              '（默认模式下多一个「复制识别内容」，排在最后；多页时变成'
              '「结束并上传」「继续添加页」「取消多页」）。'
              '滚轮滚动内容，识别进行中的提示贴在内容区**下部**。'
              '开关悬浮窗也可以在托盘右键菜单里切。',
        ),
      ],
    );
  }

  /// 一种外观（单选）：选中即写库。
  Widget _aspectRow(FloatWindowAspect a, AppSettings app, double scale) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = a.id == app.floatWindowAspect;
    final w = a.widthAt(scale).round();
    final h = a.heightAt(scale).round();
    return SettingsRow(
      key: ValueKey('settings-float-aspect-${a.id}'),
      icon: selected ? Icons.radio_button_checked : Icons.radio_button_off,
      title: a.label,
      subtitle: selected
          ? '已选择 · 当前窗口 $w×$h（${a.hint} @100%）'
          : '${a.hint} 逻辑像素 @100%',
      onTap: () => _save(app.copyWith(floatWindowAspect: a.id)),
      trailing: selected
          ? Text('使用中',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.primary))
          : null,
    );
  }

  /// 选配色的同时摆好明暗模式（M43 第 3 条）。
  ///
  /// 「纯净白」「紫罗兰」在浅色下正文/答案与底色对比度太低（用户报「颜色和背景色
  /// 高度接近，不明显」），所以选到这两套时**同时切到深色模式**；选别的配色只改配色，
  /// 不动用户自己选的明暗模式。
  AppSettings _withPalette(AppSettings a, String id) => a.copyWith(
        floatWindowPalette: id,
        floatWindowTheme: kFloatWindowDarkPalettes.contains(id)
            ? FloatWindowTheme.dark
            : a.floatWindowTheme,
      );

  /// 一个配色圆点（选中打勾）。
  Widget _paletteChip(FloatWindowPaletteSpec p, AppSettings app, Brightness b) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = p.id == app.floatWindowPalette;
    final seed = Color(p.seed);
    // 六套都是浅色系（M33 第 9 条），圆点底色统一用「种子色薄涂白」；
    // 想整体变深色用下面的「明暗模式」。
    final bg = Color.alphaBlend(seed.withValues(alpha: 0.16), Colors.white);
    return InkWell(
      key: ValueKey('settings-float-palette-${p.id}'),
      onTap: () => _save(_withPalette(app, p.id)),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : QuizSyncTheme.outline(b),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: seed, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(p.label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: scheme.onSurface)),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 14, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}
