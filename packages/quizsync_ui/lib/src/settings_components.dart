import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_colors.dart';

/// 设置页的统一基础组件（M9 设置页重构）。
///
/// 设计约束（用户 2026-09-19 的界面要求）：
/// - 间距只用 8 的倍数（见 [SettingsGap]），不出现 13/27/36 这类随机值。
/// - 优先「分组标题 + Divider」，不给每条设置包一张大卡片；
///   只有需要视觉隔离的内容（扫码区、状态区）才用浅色卡片。
/// - 90% 中性灰白 + 10% 品牌绿：绿色只用于选中项、开关 ON、主按钮、
///   滑块当前值、成功/已连接状态。
/// - 中文字体走系统字体（Windows 上即 Microsoft YaHei UI），不打包字体文件。
class SettingsGap {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s28 = 28.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
  static const s48 = 48.0;
}

/// 设置页尺寸规范（窗口缩放时按这些值收放，不写魔法数）。
class SettingsMetrics {
  /// 宽窗口下的左侧导航宽度。
  static const sidebarWidth = 232.0;

  /// 窄窗口下收缩成图标栏的宽度。
  static const railWidth = 60.0;

  /// 窄于该宽度就切到图标栏（Windows 桌面窗口可任意缩放）。
  static const railThreshold = 880.0;

  /// 右侧内容最大宽度：再宽也不拉满，保持可读行长。
  static const contentMaxWidth = 940.0;

  static const pagePaddingH = SettingsGap.s48;

  /// 页面纵向内边距（用户反馈 4：原来 40，模块之间显得太空）。
  static const pagePaddingV = SettingsGap.s28;

  /// 设置行最小高度。
  static const rowMinHeight = 56.0;

  /// 滑块 / 下拉等控件的推荐宽度：不要让控件拉满整行。
  static const controlWidth = 320.0;

  static const navItemHeight = 40.0;
  static const navRadius = 10.0;
}

/// 设置页排版层级：页面标题 26 / 分组标题 16 / 行标题 14.5 / 描述 12.5。
class SettingsType {
  static TextStyle pageTitle(ColorScheme s) => TextStyle(
      fontSize: 26,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: s.onSurface);

  static TextStyle pageDescription(ColorScheme s) => TextStyle(
      fontSize: 13.5, height: 1.5, color: s.onSurfaceVariant);

  /// 左导航顶部的「设置」标题。
  static TextStyle navTitle(ColorScheme s) => TextStyle(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: s.onSurface);

  static TextStyle groupTitle(ColorScheme s) => TextStyle(
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: s.onSurface);

  static TextStyle rowTitle(ColorScheme s) => TextStyle(
      fontSize: 14.5,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: s.onSurface);

  static TextStyle rowSubtitle(ColorScheme s) =>
      TextStyle(fontSize: 12.5, height: 1.5, color: s.onSurfaceVariant);

  static TextStyle aux(ColorScheme s) =>
      TextStyle(fontSize: 12, height: 1.5, color: s.onSurfaceVariant);

  static TextStyle value(ColorScheme s) => TextStyle(
      fontSize: 14.5,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: s.onSurface);
}

/// 左侧导航栏底色：浅色用卡片白，深色用比画布略亮的填充色，
/// 保证两种主题下导航栏与内容区都能分辨（内容区永远是画布色）。
Color settingsSidebarColor(Brightness b, ColorScheme scheme) =>
    b == Brightness.dark ? QuizSyncTheme.subtleFill(b) : scheme.surface;

/// 设置页局部主题：行直接铺在画布上，输入框要填卡片色才看得出边界
/// （全局 inputDecorationTheme 的填充色在浅色下与画布几乎同色）。
ThemeData settingsTheme(BuildContext context) {
  final t = Theme.of(context);
  final dark = t.brightness == Brightness.dark;
  return t.copyWith(
    inputDecorationTheme: t.inputDecorationTheme.copyWith(
      fillColor:
          dark ? QuizSyncTheme.subtleFill(Brightness.dark) : t.colorScheme.surface,
    ),
  );
}

/// 模块标题带的底色（用户反馈 3）。
///
/// 原来是 `QuizSyncTheme.subtleFill`（浅色 #F2F5F3），与卡片白 #FFFFFF 的
/// 亮度差只有 3%，用户看到的就是「标题带还是透明的」。这里改成**主色薄涂**：
/// 浅色 12% / 深色 22% 叠在卡片色上，既有明显边界，又仍然是一块干净的白底模块。
Color settingsGroupHeaderColor(Brightness b, ColorScheme scheme) =>
    Color.alphaBlend(
      scheme.primary.withValues(alpha: b == Brightness.dark ? 0.22 : 0.12),
      scheme.surface,
    );

/// 设置页的页面标题段：标题 + 说明 + 分隔线；下面每个 [SettingsGroup] 间隔 16。
///
/// 用户反馈 4：模块之间原来隔 32（外加页面上下 40 的内边距），一屏里
/// 每一个模块都离得很远，读起来要来回找。现在整体收紧一档：
/// 模块间 16、标题段后 20、页面纵向内边距 28。
class SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = QuizSyncTheme.outline(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SettingsType.pageTitle(scheme)),
        if (description != null) ...[
          const SizedBox(height: SettingsGap.s8),
          SettingsRichText(description!,
              style: SettingsType.pageDescription(scheme)),
        ],
        Padding(
          padding: const EdgeInsets.only(top: SettingsGap.s16),
          child: Divider(height: 1, thickness: 1, color: divider),
        ),
        const SizedBox(height: SettingsGap.s20),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: SettingsGap.s16),
          children[i],
        ],
      ],
    );
  }
}

/// 设置分组：**白色底模块卡片**（模块标题带 + 一串设置行都装在里面）。
///
/// 用户反馈 5：「选项要有模块归属，直接显示背景信息可读性差」→ 标题带；
/// 用户反馈 3（本轮）：「内容要添加白色底模块，直接显示背景导致信息可读性差」
/// → 整个分组（标题带 + 全部行）包进一张卡片色底的圆角模块里，
/// 行与行之间用分隔线断开，一眼能看出哪些选项属于同一个模块。
class SettingsGroup extends StatelessWidget {
  final String? title;
  final String? description;
  final IconData? icon;
  final List<Widget> children;

  /// 分组标题右侧的小部件（刷新按钮之类）。
  final Widget? trailing;

  /// 是否在子项之间补分隔线。整块内容（卡片、说明行）作子项时关掉更自然。
  final bool showDividers;

  const SettingsGroup({
    super.key,
    this.title,
    this.description,
    this.icon,
    this.children = const [],
    this.trailing,
    this.showDividers = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final divider = QuizSyncTheme.outline(theme.brightness);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && showDividers) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: SettingsGap.s16,
          endIndent: SettingsGap.s16,
          color: divider,
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      key: title == null ? null : ValueKey('settings-module-$title'),
      width: double.infinity,
      // 模块卡片：浅色主题下是纯白（scheme.surface），深色主题下是卡片色。
      // 原来行直接铺在画布上，画布与卡片色差很小，一屏信息糊成一片。
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: SettingsGap.s16, vertical: SettingsGap.s8),
              decoration: BoxDecoration(
                // 用户反馈 3：标题带必须有可见底色（原来是近乎透明的浅灰）。
                color: settingsGroupHeaderColor(theme.brightness, scheme),
                border: Border(bottom: BorderSide(color: divider)),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: scheme.primary),
                    const SizedBox(width: SettingsGap.s8),
                  ],
                  Expanded(
                    child: Text(title!,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        )),
                  ),
                  ?trailing,
                ],
              ),
            ),
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SettingsGap.s16, SettingsGap.s8, SettingsGap.s16, 0),
              child: SettingsRichText(description!,
                  style: SettingsType.rowSubtitle(scheme)),
            ),
          ],
          if (children.isNotEmpty) ...[
            if (title != null || description != null)
              const SizedBox(height: SettingsGap.s4),
            ...rows,
            const SizedBox(height: SettingsGap.s4),
          ],
        ],
      ),
    );
  }
}

/// 说明文字是否真的可展示：空串 / 纯空白等同于「没有说明」。
///
/// 用户反馈 2（M14）暴露的正是这一点：只要 `info != null` 就渲染 ⓘ，
/// 传了空串时会留一个点不动、悬停也没内容的死图标。没有文字就干脆不画。
bool _hasInfo(String? info) => info != null && info.trim().isNotEmpty;

/// 设置页说明文字里的**重点标记**渲染（M44 第 6 条）。
///
/// 说明文案一直用 `**…**` 标重点，但控件只是 `Text(...)`，于是用户在界面上
/// 直接看到一对星号（用户原话：「设置中部分说明文字还存在 **」）。这里统一把
/// 成对的 `**` 解析成**真加粗**，其余原样：
/// - 成对出现 → 中间那段加粗（`FontWeight.w600`），星号本身不显示；
/// - 落单（只有一个或奇数个）→ **原样显示星号**，绝不吞掉用户能看到的字符；
/// - `****`（例如「尾 4 位 ****1234」这种掩码）→ 不成对，原样保留。
List<TextSpan> settingsMarkdownSpans(String text, TextStyle style) {
  final spans = <TextSpan>[];
  var index = 0;
  while (index < text.length) {
    final start = text.indexOf('**', index);
    if (start < 0) break;
    final end = text.indexOf('**', start + 2);
    if (end < 0) break; // 落单的 `**`：原样留在最后一段里
    if (end == start + 2) {
      // `****`（连着的四个星号，例如「尾 4 位 ****1234」这种掩码）不成对：
      // 把第一个 `**` 当普通文字吐出去，继续往后找。
      if (start > index) {
        spans.add(TextSpan(text: text.substring(index, start), style: style));
      }
      spans.add(TextSpan(text: '**', style: style));
      index = start + 2;
      continue;
    }
    if (start > index) {
      spans.add(TextSpan(text: text.substring(index, start), style: style));
    }
    spans.add(TextSpan(
      text: text.substring(start + 2, end),
      style: style.copyWith(fontWeight: FontWeight.w600),
    ));
    index = end + 2;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index), style: style));
  }
  return spans;
}

/// 一行说明文字（自动处理 `**重点**`）。设置页里所有用户可见的说明都走它。
class SettingsRichText extends StatelessWidget {
  const SettingsRichText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: settingsMarkdownSpans(text, style)),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
      );
}

/// 打开 ⓘ 的完整说明对话框。
///
/// 说明文字普遍有两三句（API Key 存储方式、Base URL 拼接规则这类），
/// 塞进 Tooltip 读不完，所以点击时给一个可滚动的对话框看全文。
Future<void> _showSettingsInfoDialog(
    BuildContext context, String title, String info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        key: const ValueKey('settings-info-dialog'),
        title: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.primary),
            const SizedBox(width: SettingsGap.s8),
            Expanded(
              child: Text(title, style: SettingsType.groupTitle(scheme)),
            ),
          ],
        ),
        content: ConstrainedBox(
          // 限死可读行长；内容再长就在对话框内滚动。
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
          child: SingleChildScrollView(
            child: SettingsRichText(info,
                style: SettingsType.pageDescription(scheme)),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('settings-info-close'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

/// 标题后的 ⓘ：悬停出 [Tooltip]，点击弹出完整说明对话框。
///
/// 用户反馈 2（M14）：「api 配置里有些名称后有 ⓘ，毫无作用」。
/// 原实现是 14px 的裸 [Icon] 外套一层 Tooltip —— 点击没有任何反应，
/// 悬停还要精准命中 14px 的小目标；现在换成 [IconButton]：
/// 命中区域固定 28×28（原来的 2 倍）、自带 hover 高亮与鼠标手型，
/// 点击给全文对话框，Tooltip 保留做快速一瞥。
class _SettingsInfoIcon extends StatelessWidget {
  const _SettingsInfoIcon({required this.title, required this.info});

  /// 用所属设置项的标题做对话框标题与稳定的测试 key。
  final String title;
  final String info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: info,
      child: IconButton(
        // 沿用旧实现的名字（`info-<标题>`），测试与自动化不必改名。
        key: ValueKey('info-$title'),
        onPressed: () => _showSettingsInfoDialog(context, title, info),
        icon: const Icon(Icons.info_outline),
        iconSize: 14,
        color: scheme.onSurfaceVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        // 固定 28×28：不跟随平台的最小触摸目标（否则安卓下这一格的排版
        // 会被撑到 48，行高跟着变，安卓设置页观感会与桌面不一致）。
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 一条设置行：标题 + 说明 + 右侧控件；可点击时给 hover 反馈。
/// 短控件（开关、按钮、药丸）用它；滑块/分段选择这类宽控件用 [SettingsField]。
class SettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? tooltip;

  /// 详细背景说明：不铺在页面上，收进标题后的 ⓘ 里（用户反馈 5）。
  final String? info;

  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.tooltip,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget body = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SettingsGap.s16, vertical: SettingsGap.s8),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: SettingsMetrics.rowMinHeight - 16),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: SettingsGap.s16),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(title,
                              style: SettingsType.rowTitle(scheme))),
                      if (_hasInfo(info)) ...[
                        const SizedBox(width: SettingsGap.s4),
                        _SettingsInfoIcon(title: title, info: info!),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    SettingsRichText(subtitle!,
                        style: SettingsType.rowSubtitle(scheme)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: SettingsGap.s16),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SettingsMetrics.navRadius),
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: body,
        ),
      );
    }
    if (tooltip != null) body = Tooltip(message: tooltip!, child: body);
    return body;
  }
}

/// 可点击的动作行（备份 / 导出 / 开源许可这类入口）：图标 + 标题 + 说明 + 右箭头。
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Icon(Icons.chevron_right,
          size: 18, color: scheme.onSurfaceVariant),
    );
  }
}

/// 宽控件设置项：标题/说明在上，控件在下（滑块、分段选择、下拉、输入框）。
/// 控件宽度默认限制在 [SettingsMetrics.controlWidth]，不要把滑块拉满整行。
class SettingsField extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final double? maxWidth;
  final CrossAxisAlignment align;

  /// 详细背景说明：收进标题后的 ⓘ（用户反馈 5）。
  final String? info;

  const SettingsField({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.maxWidth,
    this.align = CrossAxisAlignment.start,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SettingsGap.s16, vertical: SettingsGap.s8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            children: [
              Flexible(child: Text(title, style: SettingsType.rowTitle(scheme))),
              if (_hasInfo(info)) ...[
                const SizedBox(width: SettingsGap.s4),
                _SettingsInfoIcon(title: title, info: info!),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            SettingsRichText(subtitle!,
                style: SettingsType.rowSubtitle(scheme)),
          ],
          const SizedBox(height: SettingsGap.s16),
          ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: maxWidth ?? SettingsMetrics.controlWidth),
            child: child,
          ),
          const SizedBox(height: SettingsGap.s8),
        ],
      ),
    );
  }
}

/// 提示行（黄色警示 / 中性说明）：图标 + 文字。
class SettingsNote extends StatelessWidget {
  final String text;
  final bool warn;
  final IconData icon;

  const SettingsNote({
    super.key,
    required this.text,
    this.warn = false,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warn
        ? HighlightColors.incomplete(theme.brightness == Brightness.dark)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SettingsGap.s16, SettingsGap.s8, SettingsGap.s16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warn ? Icons.warning_amber_rounded : icon, size: 16, color: color),
          const SizedBox(width: SettingsGap.s8),
          Expanded(
            child: SettingsRichText(text,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: color)),
          ),
        ],
      ),
    );
  }
}

/// 统一的设置页开关（比默认 Switch 略小）。
class SettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  const SettingsSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.88,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 状态圆点（连接状态 / 成功状态）；[glow] 时给一圈同色柔光。
class SettingsStatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const SettingsStatusDot({super.key, required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 6),
        ],
      ),
    );
  }
}

/// 细进度条（今日用量这类「当前值 / 上限」的比例）。
class SettingsProgressBar extends StatelessWidget {
  final double value;
  final double width;

  const SettingsProgressBar({super.key, required this.value, this.width = 260});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: QuizSyncTheme.outline(theme.brightness),
          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
        ),
      ),
    );
  }
}

/// 单个键帽（Ctrl / Alt / A）。
class SettingsKeycap extends StatelessWidget {
  final String label;

  const SettingsKeycap({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SettingsGap.s8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? QuizSyncTheme.subtleFill(Brightness.dark) : scheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: QuizSyncTheme.outline(theme.brightness)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// 组合键键帽串：'Ctrl+Alt+A' → [Ctrl][Alt][A]。
class SettingsKeycaps extends StatelessWidget {
  final String label;

  const SettingsKeycaps({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final parts = label
        .split('+')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          SettingsKeycap(label: parts[i]),
        ],
      ],
    );
  }
}

/// 左侧导航项：图标 + 标题，选中时浅主题色底 + 主题色文字。
class SettingsSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// 稳定的测试/自动化 key 后缀（例如 'api'）。
  final String? itemKey;

  const SettingsSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
    this.itemKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    final item = Material(
      color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(SettingsMetrics.navRadius),
      child: InkWell(
        key: itemKey == null ? null : ValueKey('settings-nav-$itemKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(SettingsMetrics.navRadius),
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        child: SizedBox(
          height: SettingsMetrics.navItemHeight,
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (collapsed)
                Icon(icon, size: 20, color: fg)
              else ...[
                const SizedBox(width: SettingsGap.s16),
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: SettingsGap.s16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: SettingsGap.s8),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SettingsGap.s8, vertical: 1),
      child: collapsed ? Tooltip(message: label, child: item) : item,
    );
  }
}
