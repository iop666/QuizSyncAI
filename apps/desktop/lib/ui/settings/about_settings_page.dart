import 'package:flutter/material.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/shell_open.dart';
import '../../state/app_info.dart';

/// 关于（M9 新增；用户反馈 4/6 修订）：版本、技术栈、**字体与许可**、开源许可。
///
/// 只显示项目里真实存在的信息：应用名与版本取自 `state/app_info.dart`
/// （与 pubspec / 打包脚本同一个号），技术栈取自 AGENTS.md 实测结论，
/// 开源许可走 Flutter 自带的 LicenseRegistry。
///
/// M17 第 3 条：**补上项目地址**（用户明确要求标 GitHub）。早期这里写着
/// 「本项目没有远端仓库，所以不摆 GitHub 链接」，现在仓库已经有了：
/// `https://github.com/iop666/QuizSyncAI`。
///
/// M46 第 3 条：独立的「赞助」页整页删除，赞助支持作为**最后一组**放在这里
/// （用户要求「在设置关于的最下面加入赞助支持模块，填上我的爱发电地址」）。
/// M46 第 7 条：这一页不再写「构建脚本 / 每一轮改动」这类构建过程介绍。
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  /// MiSans 官方 FAQ（许可说明，用户反馈 1 明确要求遵守）。
  ///
  /// 用户反馈 12：地址就是 `https://hyperos.mi.com/font/faq`，
  /// **末尾不要多打 `/`**（原来写成了 `.../faq/`）。
  static const misansFaqUrl = 'https://hyperos.mi.com/font/faq';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SettingsSection(
      title: '关于',
      description: '版本、技术栈、字体许可与开源许可。',
      children: [
        Center(
          child: Column(
            children: [
              const _AboutLogo(),
              const SizedBox(height: SettingsGap.s16),
              Text(kAppName,
                  style: TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text('Windows 桌面版 · v$kAppVersion',
                  key: const ValueKey('about-version'),
                  style: SettingsType.aux(scheme)),
              const SizedBox(height: 2),
              Text('$kAppNameEn · 开源地址见下方',
                  style: SettingsType.aux(scheme)),
              const SizedBox(height: SettingsGap.s16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  kAppSummary,
                  textAlign: TextAlign.center,
                  style: SettingsType.pageDescription(scheme),
                ),
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: '项目',
          icon: Icons.code,
          children: [
            SettingsRow(
              key: const ValueKey('about-github'),
              title: 'GitHub 仓库',
              subtitle: kGitHubUrl,
              info: '仓库名 $kAppNameEn：项目源码与使用说明都在这里。',
              trailing: TextButton.icon(
                key: const ValueKey('about-open-github'),
                onPressed: () => openExternal(kGitHubUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开'),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '技术',
          icon: Icons.memory_outlined,
          children: [
            SettingsRow(
              title: 'Flutter',
              subtitle: '3.47.0 stable / Dart 3.13.0，Windows 与 Android 共用同一套核心包与界面组件',
            ),
            SettingsRow(
              title: 'Windows 端',
              subtitle: '内置 shelf 局域网服务端；截屏走 win32 GDI，支持托盘与全局热键',
            ),
            SettingsRow(
              title: 'Android 端',
              subtitle:
                  'MediaProjection 截屏 + 悬浮球，任务提交与结果同步复用同一份 Dart 逻辑',
            ),
          ],
        ),
        // 用户反馈 6：关于页必须声明**使用的字体与协议**。
        SettingsGroup(
          title: '字体与许可',
          icon: Icons.text_fields,
          children: [
            SettingsRow(
              key: const ValueKey('about-font-misans'),
              title: 'MiSans（界面字体）',
              subtitle: '随安装包分发，可变字体 MiSans-VF.ttf（覆盖 100–900 字重）',
              info: '依据小米 MiSans 官方 FAQ：MiSans 允许个人与商业免费使用，'
                  '包括把字体嵌入到软件中随软件一起分发；但**不得单独售卖或再分发'
                  '字体文件本身**，也不得修改字体名称后再次发布。'
                  '设置 → 显示设置里的「题目字重」就是直接调节它的 wght 轴。',
              trailing: TextButton.icon(
                key: const ValueKey('about-open-misans-license'),
                onPressed: () => openExternal(misansFaqUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('许可说明'),
              ),
            ),
            SettingsRow(
              title: 'MiSans 授权范围',
              subtitle: '免费商用（含随软件嵌入）；禁止单独转售 / 再分发字体文件',
              tooltip: misansFaqUrl,
            ),
            SettingsRow(
              title: 'Material Icons（图标字体）',
              subtitle: '随 Flutter 框架分发，Apache License 2.0',
              trailing: TextButton(
                key: const ValueKey('about-open-material-license'),
                onPressed: () => openExternal(
                    'https://fonts.google.com/icons?icon.set=Material+Icons'),
                child: const Text('图标库'),
              ),
            ),
            SettingsTile(
              key: const ValueKey('settings-licenses'),
              icon: Icons.article_outlined,
              title: '第三方组件许可全文',
              subtitle: '查看本项目所用全部依赖的许可证全文',
              onTap: () => showLicensePage(
                context: context,
                applicationName: kAppName,
                applicationVersion: 'v$kAppVersion',
                applicationLegalese: kAppTagline,
              ),
            ),
          ],
        ),
        const SettingsNote(
          text: '当前版本不带自动更新：升级直接安装新版安装包即可，卸载不会删除你的数据。',
        ),
        // M46 第 3 条（用户要求）：赞助支持放在**本页最下面**（所以上面那条说明
        // 要排在它前面，不能让赞助模块后面再挂一句话）。
        SettingsGroup(
          title: '赞助支持',
          icon: Icons.favorite_outline,
          description: '这个工具完全免费、开源，不弹广告，也不上传你的题目与截图；'
              '所有识别结果与图片都只存在你自己的电脑上。',
          children: [
            SettingsRow(
              key: const ValueKey('about-sponsor'),
              title: '爱发电',
              subtitle: kSponsorUrl,
              info: '如果它帮你省下了一点时间，可以请作者喝一杯咖啡，金额随意。'
                  '点「打开」会用系统默认浏览器进入爱发电主页。',
              trailing: TextButton.icon(
                key: const ValueKey('about-open-sponsor'),
                onPressed: () => openExternal(kSponsorUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 应用标识（用户反馈 4）：这里必须是**应用程序图标**（任务栏/窗口/安装包用的
/// 那一枚 `icon/QuizSync_AI.png`），不是托盘状态栏图标。
///
/// 图片资源由 `tool/make_icons.dart` 从 `icon/QuizSync_AI.png` 生成
/// （带圆角与透明边，与 Windows 任务栏上看到的一致），不依赖图标字体，
/// 因此不会因为 tree-shake 而变成空白。
class _AboutLogo extends StatelessWidget {
  const _AboutLogo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('about-logo'),
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(SettingsGap.s4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            Border.all(color: QuizSyncTheme.outline(Theme.of(context).brightness)),
      ),
      child: Image.asset(
        'assets/app_icon.png',
        key: const ValueKey('about-logo-image'),
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
