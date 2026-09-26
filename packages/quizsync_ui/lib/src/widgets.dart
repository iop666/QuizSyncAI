import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_colors.dart';

/// 双端共用的小组件（M8 界面优化）：分区卡片、状态药丸、空状态。

/// 设置页/详情页的分区卡片：标题 + 说明 + 内容，统一描边圆角。
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.children = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (children.isNotEmpty) const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 状态药丸（会话状态、服务地址、题目类型等）。
class StatusPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final bool filled;

  const StatusPill({
    super.key,
    this.icon,
    required this.label,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? color.withValues(alpha: 0.14) : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: filled ? 0.35 : 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态：大图标 + 标题 + 说明 + 可选操作。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 32, color: theme.colorScheme.primary.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 会话状态的统一配色（列表 / 详情页共用）。
({Color color, IconData icon, String label}) statusStyle(
  String status, {
  required bool dark,
}) {
  switch (status) {
    case 'queued':
      return (
        color: dark ? const Color(0xFF9AA4AE) : const Color(0xFF64748B),
        icon: Icons.schedule,
        label: '排队中'
      );
    case 'analyzing':
      return (
        color: dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
        icon: Icons.autorenew,
        label: '识别中'
      );
    case 'done':
      return (color: HighlightColors.text(dark), icon: Icons.check_circle, label: '已完成');
    case 'failed':
      return (
        color: dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
        icon: Icons.error_outline,
        label: '失败'
      );
    case 'cancelled':
      return (
        color: dark ? const Color(0xFF9AA4AE) : const Color(0xFF64748B),
        icon: Icons.cancel_outlined,
        label: '已取消'
      );
    default:
      return (
        color: dark ? const Color(0xFF9AA4AE) : const Color(0xFF64748B),
        icon: Icons.help_outline,
        label: status
      );
  }
}

/// 时长文案（分析耗时/等待多少秒）。
String formatSeconds(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m 分' : '$m 分 $s 秒';
}
