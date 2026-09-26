import 'package:flutter/material.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// 历史记录条目（M8 + 用户需求 13）：状态圆点 + 摘要 + 时间 + 来源。
/// 左侧滑出或长按都触发**二次确认**删除。
class SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  /// 返回 true 表示用户确认并已删除（用于 Dismissible 收起动画）。
  final Future<bool> Function()? onDelete;

  /// 搜索命中的关键词（为空时显示普通摘要）。
  final String keyword;

  const SessionTile({
    super.key,
    required this.session,
    required this.onTap,
    this.onDelete,
    this.keyword = '',
  });

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    final onDelete = this.onDelete;
    if (onDelete == null) return card;
    return Dismissible(
      key: ValueKey('dismiss-${session.sessionId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.error),
      ),
      child: card,
    );
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final style = statusStyle(session.status.wire, dark: dark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete == null ? null : () => onDelete!(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: session.status == TaskState.analyzing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(style.icon, size: 19, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headlineOf(session, keyword: keyword),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: session.status == TaskState.failed
                              ? style.color
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${timeLabel(session)} · ${style.label}'
                        '${session.sourceDevice == 'android-local' ? '' : ' · 来自电脑'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 会话摘要文案（列表 / 结果页共用）。
String headlineOf(Session s, {String keyword = ''}) {
  if (s.status == TaskState.failed) {
    return s.errorMessage ?? errorLabelOf(s.errorCode);
  }
  if (s.status == TaskState.analyzing) return '正在识别…';
  if (s.status == TaskState.queued) return '等待电脑上线后自动分析';
  if (s.status == TaskState.cancelled) return '已取消';
  if (s.questionCount == 0) return '未识别到题目';
  if (keyword.isNotEmpty) return '识别出 ${s.questionCount} 道题（含搜索命中）';
  return '识别出 ${s.questionCount} 道题';
}

String errorLabelOf(String? code) => switch (code) {
      'ai_timeout' => 'AI 超时，可重试',
      'ai_auth' => '主机 API Key 无效',
      'ai_rate_limited' => '触发限流，稍后重试',
      'ai_bad_response' => 'AI 返回无法解析',
      'ai_quota_exceeded' => '主机今日调用已达上限',
      'no_question_found' => '未识别到题目',
      'no_active_collection' => '主机未选择任务合集',
      _ => '分析失败${code == null ? '' : '（$code）'}',
    };

String timeLabel(Session s) {
  final t = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
