import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/ball_settings.dart';
import '../services/capture_source.dart';
import '../state/providers.dart';

/// 「识别模块设置」二级页（用户需求 11）：
/// 安卓端**所有识别相关设置**都在这里——截屏方式、悬浮球（开关/透明度/大小）、
/// 多页识别页数、权限设置（真实状态 + 跳转）。
///
/// M14 第 7 条：用户要求安卓端不再提供「图片缓存上限」选项，
/// 本地原图固定只留最近 20 张（见 `kAndroidLocalImageLimit`），故选项目整体移除。
///
/// M19 第 3 条：识别模块是**多绕一圈**的路径（手机截屏 → 局域网 → 电脑 → 第三方
/// AI → 再传回来），用户要求把这个代价写在设置里，避免以为是本机识别。
const kRecognitionSlowNote = '受限于网络延迟与 API 端响应，可能识别时间过长，不建议开启。';

/// 上面那句话的展示条：设置首页的开关与二级页顶部共用同一个组件，
/// 免得两处文案各自漂移（用户明确要求「安卓识别模块加入说明」）。
class RecognitionSlowNote extends StatelessWidget {
  const RecognitionSlowNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        HighlightColors.incomplete(theme.brightness == Brightness.dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kRecognitionSlowNote,
              key: const ValueKey('recognition-slow-note'),
              style: TextStyle(fontSize: 12.5, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class RecognitionSettingsPage extends ConsumerStatefulWidget {
  const RecognitionSettingsPage({super.key});

  @override
  ConsumerState<RecognitionSettingsPage> createState() =>
      _RecognitionSettingsPageState();
}

class _RecognitionSettingsPageState
    extends ConsumerState<RecognitionSettingsPage>
    with WidgetsBindingObserver {
  String _captureMode = 'main';
  bool _ballEnabled = false;
  PermissionStatus? _perm;
  double _ballOpacity = BallAppearance.defaultOpacity;
  double _ballSize = BallAppearance.defaultSizeDp;

  /// 拖动中的页数草稿（松手才写设置，避免每帧都落盘）。
  int? _multiPageDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置返回后立刻回读真实状态。
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final app = ref.read(androidAppProvider);
    final state = await CaptureBridgeCalls.captureState();
    final perm = await CaptureBridgeCalls.permissionStatus();
    final appearance = await BallAppearance.load(app.repo);
    if (!mounted) return;
    setState(() {
      if (state != null) {
        _captureMode = state.mode;
        _ballEnabled = state.ballVisible;
      }
      _perm = perm;
      _ballOpacity = appearance.opacity;
      _ballSize = appearance.sizeDp;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsRevisionProvider);
    final theme = Theme.of(context);
    final app = ref.watch(androidAppProvider);
    final settings = app.settings.app;

    return Scaffold(
      appBar: AppBar(
        title: const Text('识别模块设置'),
        actions: [
          IconButton(
            tooltip: '重新检查权限',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const RecognitionSlowNote(),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: '截屏方式',
            subtitle: '主路径是屏幕录制（系统授权一次后长期复用）。',
            icon: Icons.screenshot_monitor_outlined,
            children: [
              _modeTile(
                mode: 'main',
                icon: Icons.videocam_outlined,
                title: '主路径：屏幕录制（推荐）',
                subtitle: '首次授权一次，之后点悬浮球直接截屏',
              ),
              _modeTile(
                mode: 'accessibility',
                icon: Icons.accessibility_new_outlined,
                title: '备选路径：无障碍截屏',
                subtitle: 'Android 11+；不可用时自动回落主路径',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: '悬浮球',
            subtitle: '单击悬浮球＝截一张图直接识别；长按＝进入「一题多页」。',
            icon: Icons.bubble_chart_outlined,
            children: [
              SwitchListTile(
                key: const ValueKey('ball-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('显示悬浮球'),
                subtitle: const Text('在其他应用上也能一键截屏'),
                value: _ballEnabled,
                onChanged: _toggleBall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _sliderRow(
                label: '透明度',
                value: _ballOpacity,
                min: BallAppearance.minOpacity,
                max: BallAppearance.maxOpacity,
                display: '${(_ballOpacity * 100).round()}%',
                onChanged: (v) => setState(() => _ballOpacity = v),
                onChangeEnd: _saveAppearance,
              ),
              _sliderRow(
                label: '大小',
                value: _ballSize,
                min: BallAppearance.minSizeDp,
                max: BallAppearance.maxSizeDp,
                display: '${_ballSize.round()} dp',
                onChanged: (v) => setState(() => _ballSize = v),
                onChangeEnd: _saveAppearance,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: '一题多页',
            subtitle: '一张图放不下一道题时用：每页立即上传，收尾后一次性识别。',
            icon: Icons.filter_none,
            children: [
              Text(
                // 用户需求 5：明确写出「长按截一张 → 松手 → 再长按下一张 → 最后短按收尾」。
                // M49：短按只提交已截取的页（不再补截一张），与 Windows 端热键一致。
                key: const ValueKey('multipage-help'),
                '一题多页：「长按」悬浮球截取第 1 张（松手即完成一页）→ 再「长按」截取第 2 张'
                ' → 以此类推（最多 ${settings.multiPageLimit} 张）→ 最后「短按」悬浮球收尾，'
                '本次所有截图会作为一道题一起识别。收尾的短按只提交已经截好的页，'
                '不会再多截一张；抓满上限会自动提交。',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.6),
              ),
              const SizedBox(height: AppSpacing.sm),
              _sliderRow(
                label: '单次最多页数',
                value: (_multiPageDraft ?? settings.multiPageLimit).toDouble(),
                min: 1,
                max: kHardMaxPagesPerTask.toDouble(),
                divisions: kHardMaxPagesPerTask - 1,
                display: '${_multiPageDraft ?? settings.multiPageLimit} 页',
                onChanged: (v) => setState(() => _multiPageDraft = v.round()),
                onChangeEnd: (v) {
                  setState(() => _multiPageDraft = null);
                  app.settings.updateApp(
                      app.settings.app.copyWith(multiPageLimit: v.round()));
                },
              ),
              Text(
                '主机侧硬上限为 $kHardMaxPagesPerTask 页，超过会被服务端拒绝。',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: '权限设置',
            subtitle: '缺哪一项，点进去开好再回来（返回本页会自动刷新）。',
            icon: Icons.verified_user_outlined,
            children: [
              _PermissionTile(
                icon: Icons.notifications_active_outlined,
                title: '通知权限',
                subtitle: '缺失：截屏服务无法常驻（Android 14+ 硬性要求），后台完成也没有提醒',
                granted: _perm?.notifications,
                onTap: () => _open(CaptureBridgeCalls.openNotificationSettings),
              ),
              _PermissionTile(
                icon: Icons.picture_in_picture_alt_outlined,
                title: '悬浮窗权限',
                subtitle: '缺失：悬浮球不显示，无法一键截屏',
                granted: _perm?.overlay,
                onTap: () => _open(CaptureBridgeCalls.openOverlaySettings),
              ),
              _PermissionTile(
                icon: Icons.battery_saver_outlined,
                title: '电池优化白名单',
                subtitle: '缺失：后台可能被系统杀掉，截屏服务中断',
                granted: _perm?.battery,
                onTap: () => _open(CaptureBridgeCalls.openBatterySettings),
              ),
              _PermissionTile(
                icon: Icons.touch_app_outlined,
                title: '无障碍（备选截屏路径）',
                subtitle: '仅借用系统的 takeScreenshot 能力，不读取屏幕内容；主路径失败时自动回落',
                granted: _perm?.accessibility,
                onTap: () => _open(CaptureBridgeCalls.openAccessibilitySettings),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // 用户需求 6：不点名任何系统/品牌，只给通用说法。
                      '部分系统需要额外允许「后台运行、自启动」，'
                      '否则悬浮球或截屏服务可能在息屏后被系统回收。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeTile({
    required String mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _captureMode == mode;
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: () => _setMode(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    int? divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    String Function(double)? draftLabel,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 78, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: (v) {
              onChanged(v);
              if (draftLabel != null) setState(() {});
            },
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            draftLabel == null ? display : draftLabel(value),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  void _setMode(String mode) {
    setState(() => _captureMode = mode);
    CaptureBridgeCalls.setCaptureMode(mode);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mode == 'main'
            ? '已切换到主路径：屏幕录制'
            : '已切换到备选路径：无障碍截屏（不可用时自动回落）')));
  }

  Future<void> _saveAppearance(double _) async {
    final app = ref.read(androidAppProvider);
    await BallAppearance.save(app.repo,
        opacity: _ballOpacity, sizeDp: _ballSize);
    await CaptureBridgeCalls.setBallAppearance(
        opacity: _ballOpacity, sizeDp: _ballSize);
  }

  Future<void> _toggleBall(bool v) async {
    if (v) {
      // 先权限、后悬浮球：悬浮窗权限缺失时引导去开，不静默失败。
      final availability = await MethodChannelCaptureSource().availability();
      if (!mounted) return;
      if (!availability.overlayGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('需要先授予「悬浮窗」权限，已为你打开设置')));
        await CaptureBridgeCalls.openOverlaySettings();
        await _load();
        return;
      }
      final notified = await CaptureBridgeCalls.requestNotificationPermission();
      if (!mounted) return;
      if (!notified) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('建议授予通知权限，保持截屏服务常驻')));
      }
    }
    final shown = await CaptureBridgeCalls.setBallVisible(v);
    // M47：开关要**落库** —— 否则重启或任何一次设置变更都会把球又打开。
    await BallAppearance.saveEnabled(ref.read(androidAppProvider).repo, v);
    if (!mounted) return;
    setState(() => _ballEnabled = v && (shown || !v));
    if (v && !shown) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('悬浮球显示失败：请检查悬浮窗权限')));
    }
    await _load();
  }

  Future<void> _open(Future<void> Function() action) async {
    await action();
    // 有些 ROM 回来后不触发 resumed，多刷一次保证状态是新的。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _load();
  }
}

/// 权限项：真实状态 + 跳转（原 `permissions_page.dart` 的内容整合到这里）。
class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? granted;
  final Future<void> Function() onTap;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = granted == null
        ? theme.colorScheme.onSurfaceVariant
        : granted!
            ? HighlightColors.text(dark)
            : theme.colorScheme.error;
    final label = granted == null ? '未知' : (granted! ? '已授予' : '未授予');
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: () => onTap(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      StatusPill(
                        icon: granted == true
                            ? Icons.check_circle
                            : (granted == false
                                ? Icons.error_outline
                                : Icons.help_outline),
                        label: label,
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
