import 'package:flutter/material.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// 「下一轮识别」悬浮窗（用户需求 3 + 用户反馈 M16 第 3 条）。
///
/// 两个页面共用同一份：**.当前任务页**（钉在列表最上方）与**结果页**
/// （浮在结果内容之上）。抽出来是为了两边的文案、图标、动效不会各写一套。
class NextRoundBanner extends StatelessWidget {
  const NextRoundBanner({
    super.key,
    required this.text,
    required this.spinning,
    this.textKey,
    this.opacity = 1,
  });

  final String text;

  /// true = 转圈（识别中）；false = 对勾（识别完成）。
  final bool spinning;

  /// 文案的 Key（测试断言用；两个页面各给一个，避免互相串）。
  final Key? textKey;

  /// 悬浮窗底色的不透明度（M18 第 3 条：结果页上那条要求 0.85）。
  ///
  /// 只作用在**卡片底色**上，文案与图标保持完全不透明 —— 整窗 `Opacity` 会把
  /// 字也一起变淡，压在题目上时反而更难读。1 = 完全不透明（「当前任务」页那条
  /// 是钉在列表最上方的，不悬在内容之上，保持默认）。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      color: theme.colorScheme.primaryContainer.withValues(alpha: opacity),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            if (spinning)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(Icons.check_circle,
                  size: 18, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                key: textKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
