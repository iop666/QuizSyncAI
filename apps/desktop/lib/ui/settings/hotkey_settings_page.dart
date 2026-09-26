import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/hotkeys.dart';
import '../../state/app_scope.dart';

/// 热键设置（用户反馈 6：整个热键模块与设置页重写；M46 第 1 条改成**两个**热键）。
///
/// 两个用途各自一个模块块：显示**实际生效**的组合键（键帽）、注册状态与原因，
/// 可以逐个自定义或恢复默认。
///
/// M12（用户反馈 5/10）：
/// - 进入本页时**暂停**全部全局热键，离开时恢复 —— 否则在页面上按组合键
///   会真的触发一次截屏识别；
/// - 去掉「重新注册全部热键」按钮（连点会触发旧实现的串键 bug），
///   改成「恢复默认热键」：一键清掉自定义组合键。
///
/// M31 重写暂停的实现：本页只负责「登记自己正在挂载」，**不再注销热键**。
/// 是否吞掉一次触发由 `_DesktopShell._hotkeyBlocked()` 在触发那一刻判断
/// （本页挂载 **且** 本窗口是前台窗口）。原来的「进页注销、离页重注册」在
/// 「窗口收进托盘 / 页面没被卸载」时会把热键永久锁死（用户实测）。
class HotkeySettingsPage extends ConsumerStatefulWidget {
  const HotkeySettingsPage({super.key});

  @override
  ConsumerState<HotkeySettingsPage> createState() => _HotkeySettingsPageState();
}

class _HotkeySettingsPageState extends ConsumerState<HotkeySettingsPage> {
  StateController<bool>? _suspended;

  @override
  void initState() {
    super.initState();
    _suspended = ref.read(hotkeysSuspendedProvider.notifier);
    // 在 build 期间改 provider 会被 Riverpod 拦下，放到首帧之后。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suspended?.state = true;
    });
  }

  @override
  void dispose() {
    // 不能在 unmount 过程中直接改 provider（Riverpod 会抛
    // StateNotifierListenerError，实测最小窗口尺寸用例就是这么炸的），
    // 放到微任务里恢复；容器已销毁时忽略即可。
    final s = _suspended;
    if (s != null) {
      scheduleMicrotask(() {
        try {
          s.state = false;
        } catch (_) {}
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(hotkeyStatusProvider);
    final app = ref.watch(settingsProvider).app;
    final custom =
        app.hotkeyJson != null || app.multipageHotkeyJson != null;

    return SettingsSection(
      title: '热键设置',
      description: '两个用途各自注册一个全局热键，默认是 **F8**（截屏识别）与 '
          '**F9**（多页模式），在后台随时可按；被其他程序占用时会自动换到下一个'
          '可用候选键。',
      children: [
        // 用户反馈 5 + M30 + M31：本页会吞掉热键触发，必须让用户知道（否则会以为热键坏了）。
        // 注意「暂停」的准确范围（M31 重写后）：只在本页**停在最前面**时忽略，
        // 切到别的程序 / 关掉本页立刻恢复 —— 文案必须说清，不然又会以为热键失效。
        const SettingsNote(
          text: '⏸ 停在本页时按键不会有任何反应（避免设置热键时误触发截屏）；'
              '离开本页、或切到别的程序，热键立刻恢复。',
        ),
        SettingsGroup(
          title: '截屏识别',
          icon: Icons.crop_free,
          description: '不在多页模式时＝截一张屏立刻识别；正在多页模式里时＝'
              '结束多页，把已抓的图一起上传识别。',
          showDividers: false,
          children: [
            _SlotRow(
              slot: HotkeySlot.capture,
              status: statuses[HotkeySlot.capture],
              customJson: app.hotkeyJson,
              onEdit: (hk) => _saveCustom(HotkeySlot.capture, hk),
              onClear: () => _clear(HotkeySlot.capture),
            ),
          ],
        ),
        SettingsGroup(
          title: '多页模式',
          icon: Icons.layers_outlined,
          description: '一道题跨了几屏时：按第一下进入多页并抓第一张，继续按追加；'
              '抓满 6 张自动上传识别，不满就按「截屏识别」结束并上传。',
          showDividers: false,
          children: [
            _SlotRow(
              slot: HotkeySlot.multipage,
              status: statuses[HotkeySlot.multipage],
              customJson: app.multipageHotkeyJson,
              onEdit: (hk) => _saveCustom(HotkeySlot.multipage, hk),
              onClear: () => _clear(HotkeySlot.multipage),
            ),
          ],
        ),
        SettingsGroup(
          title: '其他',
          icon: Icons.more_horiz,
          children: [
            SettingsRow(
              key: const ValueKey('settings-hotkey-defaults-row'),
              title: '恢复默认热键',
              subtitle: '把两个用途都改回默认键：截屏识别 F8 · 多页模式 F9',
              info: '会清掉你自己设过的组合键（包括被别的程序占用而自动回退的那些），'
                  '然后立刻按默认键重新注册。原来的「重新注册全部热键」按钮'
                  '连点多次会留下重复注册，所以改成这个一键复原。',
              trailing: OutlinedButton.icon(
                key: const ValueKey('settings-hotkey-restore-defaults'),
                onPressed: custom ? () => _restoreDefaults() : null,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('恢复默认'),
              ),
            ),
            const SettingsRow(
              title: '托盘菜单',
              subtitle: '热键被占用时，托盘右键菜单里有同样的两项操作',
            ),
          ],
        ),
        const SettingsNote(
          text: '全局热键由本程序直接向系统注册：注册失败会立刻换下一个候选键，'
              '失败原因也会写进日志（设置页不会假装成功）。',
        ),
      ],
    );
  }

  /// 一键恢复默认：清掉两个槽位的自定义键，注册逻辑随即按默认键重来。
  Future<void> _restoreDefaults() async {
    final s = ref.read(settingsProvider);
    await s.updateApp(s.app.copyWith(
      clearHotkey: true,
      clearMultipageHotkey: true,
    ));
  }

  Future<void> _saveCustom(HotkeySlot slot, HotKey hk) async {
    final s = ref.read(settingsProvider);
    final json = jsonEncode(hk.toJson());
    await s.updateApp(switch (slot) {
      HotkeySlot.capture => s.app.copyWith(hotkeyJson: json),
      HotkeySlot.multipage => s.app.copyWith(multipageHotkeyJson: json),
    });
  }

  Future<void> _clear(HotkeySlot slot) async {
    final s = ref.read(settingsProvider);
    await s.updateApp(switch (slot) {
      HotkeySlot.capture => s.app.copyWith(clearHotkey: true),
      HotkeySlot.multipage => s.app.copyWith(clearMultipageHotkey: true),
    });
  }
}

/// 一个槽位一行：标题 + 状态说明 + 生效键帽 + 自定义/恢复默认。
class _SlotRow extends ConsumerWidget {
  final HotkeySlot slot;
  final HotkeyStatus? status;
  final String? customJson;
  final Future<void> Function(HotKey hk) onEdit;
  final Future<void> Function() onClear;

  const _SlotRow({
    required this.slot,
    required this.status,
    required this.customJson,
    required this.onEdit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = status?.activeLabel;
    final custom = customJson != null && customJson!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsRow(
          key: ValueKey('settings-hotkey-${slot.name}'),
          title: switch (slot) {
            HotkeySlot.capture => '截取屏幕并识别',
            HotkeySlot.multipage => '多页模式',
          },
          subtitle: status == null
              ? '正在注册…'
              : (status!.ok ? status!.message : '未注册'),
          trailing: Wrap(
            spacing: SettingsGap.s16,
            runSpacing: SettingsGap.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (active == null)
                Icon(Icons.error_outline, size: 18, color: scheme.error)
              else
                SettingsKeycaps(
                  key: ValueKey('settings-hotkey-caps-${slot.name}'),
                  label: active,
                ),
              OutlinedButton(
                key: ValueKey('settings-hotkey-edit-${slot.name}'),
                onPressed: () => _edit(context),
                child: Text(custom ? '修改' : '自定义'),
              ),
              if (custom)
                TextButton(
                  key: ValueKey('settings-hotkey-auto-${slot.name}'),
                  onPressed: () => onClear(),
                  child: const Text('恢复默认'),
                ),
            ],
          ),
        ),
        // 只有「彻底没注册上」才额外给一条黄色警示：
        // 回退的情况 status.message 里已经写明了原因，不重复刷屏。
        if (status != null && !status!.ok)
          SettingsNote(text: status!.message, warn: true),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final current = _parse(customJson);
    final picked = await showDialog<HotKey>(
      context: context,
      builder: (_) => _HotkeyEditDialog(slot: slot, initial: current),
    );
    if (picked == null) return;
    await onEdit(picked);
  }

  static HotKey? _parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return HotKey.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// 录入组合键的对话框。
///
/// 注意：`HotKeyRecorder` 一挂到树上就监听全局键盘并把每次按键当成录入
/// （原来它常驻设置页，导致在设置页里打字会改掉截图热键），所以只在
/// 打开这个对话框时才创建它。
class _HotkeyEditDialog extends StatefulWidget {
  final HotkeySlot slot;
  final HotKey? initial;

  const _HotkeyEditDialog({required this.slot, this.initial});

  @override
  State<_HotkeyEditDialog> createState() => _HotkeyEditDialogState();
}

class _HotkeyEditDialogState extends State<_HotkeyEditDialog> {
  HotKey? _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _onRecorded(HotKey hk) {
    final reason = hotkeyRejectReason(hk);
    if (reason != null) {
      setState(() {
        _error = reason;
        _draft = null;
      });
      return;
    }
    setState(() {
      _draft = hk;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final draft = _draft;
    return AlertDialog(
      title: Text('设置「${widget.slot.title}」热键'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('点下面的输入框，然后按下新的组合键（松开即录入）。',
                style: SettingsType.rowSubtitle(scheme)),
            const SizedBox(height: SettingsGap.s16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(SettingsGap.s8),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? QuizSyncTheme.subtleFill(Brightness.dark)
                    : scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: QuizSyncTheme.outline(theme.brightness)),
              ),
              child: HotKeyRecorder(
                initalHotKey: widget.initial,
                onHotKeyRecorded: _onRecorded,
              ),
            ),
            if (draft != null) ...[
              const SizedBox(height: SettingsGap.s16),
              Row(
                children: [
                  Text('将设置为', style: SettingsType.rowSubtitle(scheme)),
                  const SizedBox(width: SettingsGap.s8),
                  SettingsKeycaps(label: hotkeyLabelOf(draft)),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: SettingsGap.s8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: SettingsGap.s8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.5, color: scheme.error)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          key: const ValueKey('settings-hotkey-save'),
          onPressed: draft == null ? null : () => Navigator.pop(context, draft),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
