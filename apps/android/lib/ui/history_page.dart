import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/android_sync.dart';
import '../state/providers.dart';
import 'result_page.dart';
import 'session_tile.dart';

/// 本机刚删完东西（记录 / 合集）就**立刻推一次 op**，别等下次冷启动。
///
/// M50 真机实测：手机上删掉一条记录后，App 保持前台十几秒不推、切后台再回
/// 前台（socket 未断）也不推 —— 只有冷启动才会把积压的 op 一起推上去，用户
/// 观感就是「手机上删了、电脑上还在」。这里在删除之后主动推一次。
void _pushLocalOps(WidgetRef ref) {
  final pairing = ref.read(pairingProvider);
  if (pairing == null) return; // 没配对：本地删除照常，等配对后再同步
  unawaited(AndroidSync(app: ref.read(androidAppProvider))
      .pushOpsOnly(pairing));
}

/// 历史记录 tab（用户需求 8/9/13）：
/// 先按**合集**分组（本地库来自同步），点进合集看该合集的识别记录，
/// 再点进记录看题目；搜索时退化为平铺的命中列表。
/// 删除走二次确认（滑动或长按）。
///
/// 用户需求 A：**安卓端不再有导出/分享入口**——安卓是结果显示器，
/// 导出在 Windows 端做（`services/collection_export.dart` 打 Markdown 文件
/// 的能力保留给桌面端与单测，界面上不再出现分享按钮）。
class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';
  Set<String> _hits = {};
  Timer? _debounce;

  /// 正在「选中删除」的合集 id（M18 第 2 条：用户要求「安卓端可以选中删除合集」）。
  ///
  /// 非空 = 进入多选模式：点合集变「选中 / 取消选中」，顶部出现一条操作栏
  /// （已选 N 个 · 取消 · 删除）。用「长按进入」而不是给每个卡片加一个删除图标，
  /// 是为了不把「点开合集看记录」这个主操作挤掉（与记录列表的滑动/长按删除同风格）。
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final keyword = raw.trim();
    if (keyword.isEmpty) {
      setState(() {
        _keyword = '';
        _hits = {};
      });
      return;
    }
    setState(() => _keyword = keyword);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final hits = await ref
          .read(androidAppProvider)
          .repo
          .searchQuestions(keyword);
      if (!mounted || _keyword != keyword) return;
      setState(() => _hits = hits.map((q) => q.sessionId).toSet());
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _keyword = '';
      _hits = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_selecting) _selectionBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            key: const ValueKey('search-box'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索题干 / 解析',
              suffixIcon: _keyword.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close),
                      onPressed: _clearSearch,
                    ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _keyword.isEmpty ? _groupList() : _searchResults(),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 选中删除合集（M18 第 2 条）
  // ------------------------------------------------------------

  void _toggleSelection(String collectionId) {
    setState(() {
      if (!_selected.remove(collectionId)) _selected.add(collectionId);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// 顶部的多选操作栏（历史 tab 没有自己的 AppBar，只能画在列表上方）。
  Widget _selectionBar() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已选 ${_selected.length} 个合集',
                key: const ValueKey('collection-selection-count'),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              key: const ValueKey('collection-select-cancel'),
              onPressed: _clearSelection,
              child: const Text('取消'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const ValueKey('collection-select-delete'),
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  /// 删除选中的合集：**必须二次确认**（与记录删除同一个口径）。
  ///
  /// 只删合集本身，**不级联删除**它下面的识别记录（那批记录会回到「未分类」，
  /// 与 Windows 端的删除语义一致）。本机删除会生成一条 op 并同步给主机 ——
  /// 手机上主动删是用户的明确动作，两端一起没；反过来主机删合集**不会**让手机
  /// 丢分组（M18 第 4 条：用户要求「windows 端删除后安卓端不再同步跟着删除」）。
  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除选中的 ${ids.length} 个合集？'),
        content: const Text('合集里的识别记录不会被删除（会回到「未分类」）。'
            '本机与电脑上的这些合集都会被删除。此操作不可撤销。'),
        actions: [
          TextButton(
              key: const ValueKey('collection-delete-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('collection-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = ref.read(androidAppProvider).repo;
    for (final id in ids) {
      await repo.deleteCollection(id);
    }
    _pushLocalOps(ref); // 删完立刻推，不等冷启动（M50）
    if (!mounted) return;
    setState(_selected.clear);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionGroupsProvider);
    ref.invalidate(unclassifiedSessionsProvider);
    ref.invalidate(sessionsProvider);
    messenger?.showSnackBar(SnackBar(content: Text('已删除 ${ids.length} 个合集')));
  }

  /// 顶层：合集分组（未归属合集的记录归入「未分类」）。
  Widget _groupList() {
    final groups = ref.watch(collectionGroupsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(collectionGroupsProvider);
        await ref.read(collectionGroupsProvider.future);
      },
      child: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _message('读取历史失败：$e'),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
                const EmptyState(
                  icon: Icons.photo_camera_outlined,
                  title: '还没有识别记录',
                  message: '点悬浮球截屏，或用「相册选图搜题」上传一张题目截图。',
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
            itemCount: list.length,
            itemBuilder: (context, i) => _groupTile(list[i]),
          );
        },
      ),
    );
  }

  Widget _groupTile(CollectionGroup g) {
    final theme = Theme.of(context);
    // 「未分类」不是一个合集（只是没归属的记录），没有可删的东西。
    final selectable = !g.isUnclassified;
    final id = g.collectionId;
    final selected = id != null && _selected.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          key: ValueKey('group-${g.collectionId ?? 'unclassified'}'),
          selected: selected,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          leading: _selecting && selectable
              ? Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                )
              : Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    g.isUnclassified
                        ? Icons.folder_off_outlined
                        : Icons.folder_outlined,
                    size: 19,
                    color: theme.colorScheme.primary,
                  ),
                ),
          title: Text(g.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${g.count} 条识别记录'),
          // 多选模式下不摆「进详情」的箭头（点一下是选中而不是进入）。
          trailing: (_selecting || !selectable)
              ? null
              : Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
          // 长按 = 选中这个合集并进入多选模式（M18 第 2 条）。
          onLongPress: selectable && id != null
              ? () => _toggleSelection(id)
              : null,
          onTap: () {
            if (_selecting) {
              if (selectable && id != null) _toggleSelection(id);
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CollectionSessionsPage(
                collectionId: g.collectionId,
                title: g.title,
              ),
            ));
          },
        ),
      ),
    );
  }

  Widget _searchResults() {
    final sessions = ref.watch(sessionsProvider(null));
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _message('搜索失败：$e'),
      data: (all) {
        final list =
            all.where((s) => _hits.contains(s.sessionId)).toList();
        if (list.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
              EmptyState(
                icon: Icons.search_off,
                title: '没有匹配的记录',
                message: '关键词「$_keyword」在题干与解析里都没找到。',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('清空搜索'),
                  ),
                ],
              ),
            ],
          );
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          itemCount: list.length,
          itemBuilder: (context, i) => _tile(list[i], keyword: _keyword),
        );
      },
    );
  }

  Widget _tile(Session s, {String keyword = ''}) => SessionTile(
        session: s,
        keyword: keyword,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ResultPage(
            sessionId: s.sessionId,
            collectionId: s.collectionId,
          ),
        )),
        onDelete: () => confirmDeleteSession(context, ref, s),
      );

  Widget _message(String text) => ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          EmptyState(icon: Icons.error_outline, title: '出错了', message: text),
        ],
      );
}

/// 合集详情：该合集的识别记录（用户需求 8 的第二层）。
class CollectionSessionsPage extends ConsumerWidget {
  final String? collectionId;
  final String title;

  const CollectionSessionsPage({
    super.key,
    required this.collectionId,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = collectionId == null
        ? ref.watch(unclassifiedSessionsProvider)
        : ref.watch(sessionsProvider(collectionId));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
            icon: Icons.error_outline, title: '出错了', message: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: '这个分组还没有识别记录',
              message: '回到「当前任务」发起一次识别后，记录会出现在这里。',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: list.length,
            itemBuilder: (context, i) => SessionTile(
              session: list[i],
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ResultPage(
                  sessionId: list[i].sessionId,
                  collectionId: collectionId,
                ),
              )),
              onDelete: () => confirmDeleteSession(context, ref, list[i]),
            ),
          );
        },
      ),
    );
  }
}

/// 删除一条识别记录（用户需求 13）：**必须二次确认**，软删除并同步到主机。
Future<bool> confirmDeleteSession(
  BuildContext context,
  WidgetRef ref,
  Session session,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('删除这条识别记录？'),
      content: const Text(
          '本机与电脑上的这条记录都会被删除（软删除，会同步到主机）。此操作不可撤销。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除')),
      ],
    ),
  );
  if (ok != true) return false;
  await ref.read(androidAppProvider).repo.deleteSession(session.sessionId);
  _pushLocalOps(ref); // 删完立刻推，不等冷启动（M50）
  ref.invalidate(sessionsProvider);
  ref.invalidate(unclassifiedSessionsProvider);
  ref.invalidate(collectionGroupsProvider);
  ref.invalidate(sessionQuestionsProvider);
  messenger?.showSnackBar(const SnackBar(content: Text('已删除这条识别记录')));
  return true;
}
