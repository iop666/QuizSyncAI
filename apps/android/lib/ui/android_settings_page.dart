import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../state/app_info.dart';
import '../state/providers.dart';
import 'recognition_settings_page.dart';

/// 设置 tab（用户需求 10/11）：外观（主题模式 + 字号，**已移除配色选择**）、
/// 识别模块总开关（默认关闭）+ 二级页入口、配对、关于。
class AndroidSettingsPage extends ConsumerStatefulWidget {
  final Future<void> Function() onUnpair;

  const AndroidSettingsPage({super.key, required this.onUnpair});

  @override
  ConsumerState<AndroidSettingsPage> createState() =>
      _AndroidSettingsPageState();
}

class _AndroidSettingsPageState extends ConsumerState<AndroidSettingsPage> {
  double? _fontDraft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(settingsRevisionProvider);
    final app = ref.watch(androidAppProvider);
    final settings = app.settings;
    final fontSize = _fontDraft ?? settings.app.fontSize;
    final recognitionEnabled = settings.app.androidRecognitionEnabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        SectionCard(
          title: '识别模块',
          subtitle: '截取手机屏幕上的题目，传到电脑用 AI 分析，再把答案同步回本机。',
          icon: Icons.document_scanner_outlined,
          children: [
            SwitchListTile(
              key: const ValueKey('recognition-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('识别模块（截取图片传到电脑分析）'),
              subtitle: Text(recognitionEnabled
                  ? '已开启：悬浮球可截屏，长按进入一题多页'
                  : '已关闭：悬浮球不显示，截屏与上传入口不可用'),
              value: recognitionEnabled,
              onChanged: (v) => settings.updateApp(
                  settings.app.copyWith(androidRecognitionEnabled: v)),
            ),
            // M19 第 3 条：开启前先把代价说清楚（走局域网 + 第三方 AI，
            // 比本机识别慢得多）。开关本身不拦人，只是知情。
            const SizedBox(height: AppSpacing.sm),
            const RecognitionSlowNote(),
            if (recognitionEnabled)
              ListTile(
                key: const ValueKey('open-recognition-settings'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: const Text('识别模块设置'),
                subtitle: const Text('截屏方式、悬浮球、一题多页、权限'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RecognitionSettingsPage())),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: '外观',
          subtitle: '主题模式与字号；字号也可在结果页右上角快捷调整。',
          icon: Icons.palette_outlined,
          children: [
            SegmentedButton<ThemeMode2>(
              key: const ValueKey('theme-mode'),
              segments: const [
                ButtonSegment(value: ThemeMode2.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode2.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode2.dark, label: Text('深色')),
              ],
              selected: {settings.app.theme},
              onSelectionChanged: (v) =>
                  settings.updateApp(settings.app.copyWith(theme: v.first)),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Text('正文字号'),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 12,
                    max: 32,
                    divisions: 20,
                    label: fontSize.round().toString(),
                    onChanged: (v) => setState(() => _fontDraft = v),
                    onChangeEnd: (v) {
                      setState(() => _fontDraft = null);
                      settings.updateApp(settings.app.copyWith(fontSize: v));
                    },
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text('${fontSize.round()}', textAlign: TextAlign.end),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: '配对',
          subtitle: '本机已与电脑配对；换电脑或连不上时重新配对。',
          icon: Icons.link_outlined,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_off),
              title: const Text('解除配对'),
              subtitle: const Text('清除本机保存的 token，重新扫码可再次配对'),
              onTap: _unpair,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: '关于',
          icon: Icons.info_outline,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(kAppName),
              subtitle: const Text('局域网搜题工具 · v$kAppVersion'
                  '\n答案由 AI 生成，仅供参考'),
            ),
            // M17 第 3 条：关于页要标明项目地址。安卓端不引入 url_launcher
            // （不为一个链接加平台插件）：点一下复制地址，用户自己粘到浏览器。
            ListTile(
              key: const ValueKey('about-github'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code, size: 20),
              title: const Text('项目地址（$kAppNameEn）'),
              subtitle: const Text(kGitHubUrl),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () async {
                await Clipboard.setData(const ClipboardData(text: kGitHubUrl));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制项目地址：$kGitHubUrl')));
              },
            ),
            Row(
              children: [
                Icon(Icons.brightness_6_outlined,
                    size: 15, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // 用户反馈：切了深色状态栏没跟着变。把「应用打算用的系统栏
                    // 样式」显示出来，一眼能区分是「App 没下发」还是「ROM 忽略」。
                    '当前界面：${_themeLabel(theme)} · 状态栏'
                    '${theme.brightness == Brightness.dark ? '深底浅图标' : '浅底深图标'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _themeLabel(ThemeData theme) =>
      theme.brightness == Brightness.dark ? '深色' : '浅色';

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('解除配对？'),
        content: const Text('将清除本机的配对信息与同步凭证，之后需要重新扫码。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('解除')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onUnpair();
  }
}
