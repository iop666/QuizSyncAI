import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/live_updates.dart' show hostErrorMessage;
import '../state/providers.dart';
import 'next_round_banner.dart';
import 'result_page.dart';

/// 「当前任务」tab（用户需求 1）：**安卓默认就是 Windows 的结果显示器**。
///
/// 页面主体只有两样东西：
/// 1. 与电脑的连接状态（一行：已连接 / 未连接 / 还没选合集）；
/// 2. 电脑的任务结果（进行中 =「N 张图片识别中…」，完成 = 答案）。
///
/// 本机识别（悬浮球 / 截屏 / 相册上传）的开关、权限引导、未配对提示
/// **一概不在这里出现**——那些只留在「设置 → 识别模块」里。
/// 主机开始/结束识别靠 WS 事件（`LiveUpdates` → `RefLiveUpdateSink`）
/// invalidate provider 自动刷新，用户不需要手动下拉。
///
/// 用户需求 3 的「下一次识别」：页面上已经显示着上一轮结果时，新一轮识别
/// **不擦掉它**——只在最上方加一条悬浮窗（识别中 → 识别完成），完成后自动
/// 进入新一轮的结果页。
class CurrentTaskPage extends ConsumerStatefulWidget {
  const CurrentTaskPage({super.key});

  /// 「识别完成」悬浮窗露一下脸再自动跳页，避免硬切。
  static const Duration autoOpenDelay = Duration(milliseconds: 400);

  @override
  ConsumerState<CurrentTaskPage> createState() => _CurrentTaskPageState();
}

/// 是否该自动进入结果页（用户需求 3）：主机任务完成 + App 在前台 + 还没跳过。
///
/// 抽成纯函数是为了在没有设备的机器上也能断言「后台不抢前台」这条规则——
/// 生命周期状态来自平台通道，widget 测试里读不到。
bool shouldAutoOpenResult(ActiveTask task, AppLifecycleState? lifecycle) {
  if (!task.autoOpenResult) return false;
  // null = 还没收到生命周期事件（首帧 / 测试环境）：按前台处理。
  return lifecycle == null ||
      lifecycle == AppLifecycleState.resumed ||
      lifecycle == AppLifecycleState.inactive;
}

class _CurrentTaskPageState extends ConsumerState<CurrentTaskPage>
    with WidgetsBindingObserver {
  Timer? _autoOpenTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoOpenTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 结果是在后台到达的：不抢前台，等用户回到 App 再进结果页（只消费一次）。
    if (state == AppLifecycleState.resumed) _autoOpenIfPending();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingProvider);
    final status = ref.watch(serverStatusProvider);
    final task = ref.watch(activeTaskProvider);

    // 主机任务完成 → 自动进入本次结果页。用 ref.listen 而不是在 build 里跳转
    // （build 期间 push 会被 Flutter 拦下）；延迟一小段让「识别完成」先显示出来。
    ref.listen<ActiveTask>(activeTaskProvider, (previous, next) {
      if (!next.autoOpenResult) return;
      _autoOpenTimer?.cancel();
      _autoOpenTimer = Timer(CurrentTaskPage.autoOpenDelay, _autoOpenIfPending);
    });

    return RefreshIndicator(
      onRefresh: () => ref.read(serverStatusProvider.notifier).refresh(pairing),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          // 悬浮窗钉在页面最上方（用户需求 3）：新一轮识别中 / 新一轮已完成。
          if (task.showsPreviousResult)
            _nextBanner(context,
                text: '${task.imageCount < 1 ? 1 : task.imageCount} 张图片识别中…',
                spinning: true),
          if (task.completesIntoBanner)
            _nextBanner(context, text: '识别完成', spinning: false),
          _statusLine(context, ref, status),
          ..._resultCards(context, ref, status, task),
        ],
      ),
    );
  }

  /// 满足「前台 + 有待跳结果」时进入结果页，并把待跳标记消费掉（只跳一次）。
  void _autoOpenIfPending() {
    if (!mounted) return;
    final task = ref.read(activeTaskProvider);
    if (!shouldAutoOpenResult(task, WidgetsBinding.instance.lifecycleState)) {
      return;
    }
    final sessionId = task.sessionId;
    ref.read(activeTaskProvider.notifier).consumeAutoOpen();
    if (sessionId == null || sessionId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultPage(sessionId: sessionId),
    ));
  }

  /// 下一轮识别的悬浮窗（用户需求 3）。样式与结果页上那条共用
  /// [NextRoundBanner]（用户反馈 M16 第 3 条）。
  Widget _nextBanner(BuildContext context,
      {required String text, required bool spinning}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: NextRoundBanner(
        key: const ValueKey('next-task-banner'),
        textKey: const ValueKey('next-task-banner-text'),
        text: text,
        spinning: spinning,
      ),
    );
  }

  // ------------------------------------------------------------
  // 与电脑的连接状态：**就一行**（用户需求 1）
  // ------------------------------------------------------------

  Widget _statusLine(BuildContext context, WidgetRef ref, ServerStatus status) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final (IconData icon, String label, Color color) =
        switch (status.connection) {
      HostConnection.unpaired => (
          Icons.link_off,
          '未配对',
          theme.colorScheme.error,
        ),
      HostConnection.checking => (
          Icons.wifi_tethering,
          '正在连接电脑…',
          theme.colorScheme.onSurfaceVariant,
        ),
      HostConnection.offline => (
          Icons.wifi_off,
          '电脑未连接',
          theme.colorScheme.error,
        ),
      HostConnection.online => status.hasActiveCollection
          ? (
              Icons.check_circle,
              '已连接 · ${status.collectionName ?? status.activeCollectionId}',
              HighlightColors.text(dark),
            )
          : (
              Icons.folder_off_outlined,
              '已连接 · 电脑还没选合集',
              theme.colorScheme.error,
            ),
    };
    return Card(
      key: const ValueKey('host-status'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                key: const ValueKey('host-status-text'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: color),
              ),
            ),
            // 电脑没选合集时唯一需要的动作：让手机替主机挑一个合集。
            if (status.connection == HostConnection.online &&
                !status.hasActiveCollection)
              TextButton(
                key: const ValueKey('pick-collection'),
                onPressed: () => pickHostCollection(context, ref),
                child: const Text('选择合集'),
              ),
            IconButton(
              key: const ValueKey('refresh-host'),
              tooltip: '刷新状态',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () =>
                  ref.read(serverStatusProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // 电脑的任务结果（用户需求 1/7）
  // ------------------------------------------------------------

  List<Widget> _resultCards(BuildContext context, WidgetRef ref,
      ServerStatus status, ActiveTask task) {
    if (task.running) {
      // 用户需求 3：新一轮识别进行中时，页面上已经显示着的上一轮结果**不动**，
      // 只在最上方多一条悬浮窗（已在 build 里渲染）。
      if (task.showsPreviousResult) {
        return [
          _gap,
          // 没有「忽略」：这一轮还在跑，清空状态会把上面的进度一起擦掉。
          _doneCard(context, ref, task.shownSessionId, dismissible: false),
        ];
      }
      return [_gap, _runningCard(context, task)];
    }
    if (task.failed) {
      return [
        _gap,
        _failedCard(context, ref, task),
        // 上一轮的结果依然可见：一次失败不该把已经拿到的答案擦掉。
        if ((task.shownSessionId ?? '').isNotEmpty) ...[
          _gap,
          _doneCard(context, ref, task.shownSessionId, dismissible: false),
        ],
      ];
    }
    if (task.finished) {
      return [_gap, _doneCard(context, ref, task.sessionId)];
    }
    // 电脑已就绪但还没开始识别：给一句「等待电脑」的说明即可。
    if (status.connection == HostConnection.online &&
        status.hasActiveCollection) {
      return [_gap, _idleCard(context)];
    }
    // 其余情况（未配对 / 连接中 / 未连接 / 主机未选合集）状态行已经说清楚了。
    return const [];
  }

  static const Widget _gap = SizedBox(height: AppSpacing.md);

  /// 已连接、还没开始任务。
  ///
  /// 用户需求 4：连接状态在页面最上方的 `host-status` 卡片里已经说清楚，
  /// 这里**只说明怎么开始**，不再重复一遍「已连接」。
  Widget _idleCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('not-started'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.play_circle_outline,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('还没开始识别', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text('在电脑上按下识别热键，或截屏识别后，结果会自动出现在这里。',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runningCard(BuildContext context, ActiveTask task) {
    final theme = Theme.of(context);
    final pages = task.imageCount < 1 ? 1 : task.imageCount;
    return Card(
      key: const ValueKey('task-running'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    // 用户需求 1/7：未完成时显示「N 张图片识别中…」。
                    '$pages 张图片识别中…',
                    key: const ValueKey('task-progress-text'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('题目已上传到电脑，AI 正在读题。完成后本页会自动刷新。',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _failedCard(BuildContext context, WidgetRef ref, ActiveTask task) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('task-failed'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Text('识别失败', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(task.message ?? '主机未返回原因，可在电脑端查看日志。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => ref.read(activeTaskProvider.notifier).clear(),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一轮识别的结果：直接显示答案（用户需求 1「完成显示答案」），
  /// 需要完整解析时再点「查看结果」。
  ///
  /// [sessionId] 显式传入：新一轮识别进行中时，这张卡片显示的是**上一轮**
  /// 的结果（[ActiveTask.shownSessionId]），不是本轮的。
  /// [dismissible] = false 时不显示「忽略」——新一轮还在跑，清空状态会把
  /// 上面的进度悬浮窗一起擦掉。
  Widget _doneCard(BuildContext context, WidgetRef ref, String? sessionId,
      {bool dismissible = true}) {
    final theme = Theme.of(context);
    final questions = sessionId == null
        ? const AsyncValue<List<Question>>.data(<Question>[])
        : ref.watch(sessionQuestionsProvider(sessionId));
    return Card(
      key: const ValueKey('task-done'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: HighlightColors.text(
                        theme.brightness == Brightness.dark)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('识别完成', style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            questions.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('正在读取结果…'),
              ),
              error: (_, _) => _offlineHint(theme),
              data: (list) => list.isEmpty
                  ? _offlineHint(theme)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final q in list) _answerLine(context, q),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (dismissible)
                  TextButton(
                    onPressed: () =>
                        ref.read(activeTaskProvider.notifier).clear(),
                    child: const Text('忽略'),
                  ),
                if (dismissible) const SizedBox(width: 6),
                if (sessionId != null)
                  FilledButton.icon(
                    key: const ValueKey('open-result'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ResultPage(sessionId: sessionId)),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('查看结果'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _offlineHint(ThemeData theme) => Text(
        '结果已同步到本机，可以离线查看。',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );

  Widget _answerLine(BuildContext context, Question q) {
    final theme = Theme.of(context);
    final answer =
        q.choice.isNotEmpty ? q.choice.join('') : (q.answerText ?? '—');
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题目（序号 + 题号）与答案各占一半：用户反馈 9，原来答案是一个不受
          // 约束的 Text，长答案 / 多行结构化答案会直接顶出屏幕右边。
          Expanded(
            child: Text(
              q.displayTitle,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              answer,
              key: ValueKey('task-answer-${q.questionId}'),
              textAlign: TextAlign.end,
              softWrap: true,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: HighlightColors.text(
                      theme.brightness == Brightness.dark)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 在手机上切换主机的当前合集（用户需求 12 的友好补充）。
Future<void> pickHostCollection(BuildContext context, WidgetRef ref) async {
  final pairing = ref.read(pairingProvider);
  if (pairing == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final gateway = ref.read(hostGatewayFactoryProvider)(pairing);
    final list = await gateway.collections();
    if (!context.mounted) return;
    if (list.collections.isEmpty) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('电脑上还没有合集：请先在 Windows 端新建一个任务合集')));
      return;
    }
    final picked = await showDialog<Collection>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('选择主机当前合集'),
        children: [
          for (final c in list.collections)
            SimpleDialogOption(
              key: ValueKey('host-collection-${c.collectionId}'),
              onPressed: () => Navigator.pop(context, c),
              child: Row(
                children: [
                  if (c.collectionId == list.activeCollectionId)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check, size: 16),
                    ),
                  Expanded(child: Text(c.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await gateway.selectCollection(picked.collectionId);
    ref.read(serverStatusProvider.notifier).applyCollection(
          picked.collectionId,
          picked.name,
        );
    messenger?.showSnackBar(
        SnackBar(content: Text('已把主机的当前合集切换为「${picked.name}」')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(hostErrorMessage(e))));
  }
}
