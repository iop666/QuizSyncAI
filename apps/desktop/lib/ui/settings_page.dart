import 'package:flutter/material.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../state/app_info.dart';
import 'settings/about_settings_page.dart';
import 'settings/api_settings_page.dart';
import 'settings/ball_settings_page.dart';
import 'settings/data_settings_page.dart';
import 'settings/device_settings_page.dart';
import 'settings/display_settings_page.dart';
import 'settings/float_window_settings_page.dart';
import 'settings/guide_settings_page.dart';
import 'settings/hotkey_settings_page.dart';
import 'settings/recognition_settings_page.dart';

/// 设置页（M9 重构）：左侧固定导航 + 右侧独立滚动的内容区。
///
/// 信息架构（用户 2026-09-19 要求；M32 用户需求 5 把「使用说明」提到第一项；
/// M46 第 3 条删掉独立「赞助」页，赞助入口挪到「关于」页最下面）：
/// 使用说明 / 显示设置 / API 配置 / 连接设备 / 识别设置 / 悬浮球设置 /
/// 悬浮窗设置 / 热键设置 / 数据管理 / 关于。
/// 左栏只负责「我在哪里」，右栏只负责「我能设置什么」——右侧只出现该分类的内容，
/// 不再是一条很长、所有设置混在一起的页面。业务逻辑与数据结构完全不变。
enum SettingsTab {
  // M32 用户需求 5：第一项必须是「使用说明」，其余顺序整体后延一位。
  guide('使用说明', '可识别的方式与各项设置怎么用', Icons.menu_book_outlined),
  display('显示设置', '界面外观与文字大小', Icons.palette_outlined),
  api('API 配置', 'AI 服务、API Key 与调用限制', Icons.auto_awesome_outlined),
  device('连接设备', '与手机的局域网连接、配对与设备', Icons.wifi_tethering),
  recognition('识别设置', '自动识别、多页识别与本地图片缓存',
      Icons.center_focus_strong_outlined),
  // 用户反馈 11：悬浮球设置夹在「识别设置」与「热键设置」之间。
  ball('悬浮球设置', '桌面悬浮球的开关、大小、透明度与描边',
      Icons.bubble_chart_outlined),
  // M32 用户需求 1：悬浮窗设置紧跟在悬浮球后面（两者都是桌面浮层）。
  floatWindow('悬浮窗设置', '桌面悬浮窗的开关、位置、比例与显示模式',
      Icons.select_all_outlined),
  hotkey('热键设置', '截屏识别与多页模式两个快捷键', Icons.keyboard_outlined),
  data('数据管理', '任务合集、导出、备份与日志', Icons.folder_outlined),
  // M46 第 3 条：赞助支持挂在「关于」页最下面，不再单独占一栏。
  about('关于', '版本、技术栈与开源许可', Icons.info_outline);

  const SettingsTab(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  /// [initialTab] 供托盘/测试直接落到某个分类；导航点击仍以页面内状态为准。
  const SettingsPage({super.key, this.initialTab = SettingsTab.guide});

  final SettingsTab initialTab;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsTab _tab = widget.initialTab;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(SettingsTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // 换分类后回到顶部，否则会停在上一页滚到的位置。
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final collapsed =
              constraints.maxWidth < SettingsMetrics.railThreshold;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: collapsed
                    ? SettingsMetrics.railWidth
                    : SettingsMetrics.sidebarWidth,
                child: _SettingsNav(
                  tab: _tab,
                  collapsed: collapsed,
                  onSelect: _select,
                ),
              ),
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: QuizSyncTheme.outline(theme.brightness)),
              // 只有右侧内容区滚动：左栏固定不动。
              Expanded(
                child: Theme(
                  data: settingsTheme(context),
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.symmetric(
                        horizontal: collapsed
                            ? SettingsGap.s32
                            : SettingsMetrics.pagePaddingH,
                        vertical: SettingsMetrics.pagePaddingV,
                      ),
                      child: Align(
                        // 用户反馈 8：内容区原来靠左，界面缩放调小后右侧会空出
                        // 一大片画布（深色主题下就是一片黑）。改为居中，
                        // 视觉上「窗口边界＝内容边界」。
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: SettingsMetrics.contentMaxWidth),
                          child: _SettingsContent(tab: _tab),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 左侧导航：固定宽度、固定不滚动，顶部「设置」+ 返回，底部版本号。
class _SettingsNav extends StatelessWidget {
  final SettingsTab tab;
  final bool collapsed;
  final ValueChanged<SettingsTab> onSelect;

  const _SettingsNav({
    required this.tab,
    required this.collapsed,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();
    return Container(
      color: settingsSidebarColor(theme.brightness, scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                collapsed ? SettingsGap.s8 : SettingsGap.s16,
                SettingsGap.s24,
                collapsed ? SettingsGap.s8 : SettingsGap.s16,
                SettingsGap.s16),
            child: Row(
              children: [
                if (canPop)
                  IconButton(
                    key: const ValueKey('settings-back'),
                    tooltip: '返回',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                if (canPop && !collapsed) const SizedBox(width: SettingsGap.s8),
                if (!collapsed)
                  Text('设置', style: SettingsType.navTitle(scheme)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: SettingsGap.s8),
              children: [
                for (final t in SettingsTab.values)
                  SettingsSidebarItem(
                    icon: t.icon,
                    label: t.label,
                    selected: t == tab,
                    collapsed: collapsed,
                    itemKey: t.name,
                    onTap: () => onSelect(t),
                  ),
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SettingsGap.s24, SettingsGap.s8, SettingsGap.s16, SettingsGap.s24),
              child: Text('$kAppName v$kAppVersion',
                  key: const ValueKey('settings-version'),
                  style: SettingsType.aux(scheme)),
            ),
        ],
      ),
    );
  }
}

/// 右侧内容：切分类时**不做任何过渡动画**（用户反馈 3：删掉切换动效）。
class _SettingsContent extends StatelessWidget {
  final SettingsTab tab;

  const _SettingsContent({required this.tab});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(tab),
      child: switch (tab) {
        SettingsTab.guide => const GuideSettingsPage(),
        SettingsTab.display => const DisplaySettingsPage(),
        SettingsTab.api => const ApiSettingsPage(),
        SettingsTab.device => const DeviceSettingsPage(),
        SettingsTab.recognition => const RecognitionSettingsPage(),
        SettingsTab.ball => const BallSettingsPage(),
        SettingsTab.floatWindow => const FloatWindowSettingsPage(),
        SettingsTab.hotkey => const HotkeySettingsPage(),
        SettingsTab.data => const DataSettingsPage(),
        SettingsTab.about => const AboutSettingsPage(),
      },
    );
  }
}
