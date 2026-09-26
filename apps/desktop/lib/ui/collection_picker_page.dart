import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../state/app_scope.dart';
import '../state/collections.dart';

/// 任务合集选择（用户需求 8）：
/// Windows **每次打开**都必须先选中一个合集；不存在任何合集时先新建并命名。
/// 所有识别都落在当前选中的合集里（安卓端历史记录也按合集分组）。
class CollectionGate extends ConsumerWidget {
  final Widget child;

  const CollectionGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final active = ref.watch(activeCollectionProvider);

    // 合集列表还在读：短暂转圈，避免闪一下选择页。
    if (collections.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (active == null) {
      return CollectionPickerPage(firstRun: collections.valueOrNull?.isEmpty ?? true);
    }
    return child;
  }
}

/// 合集选择页（`firstRun` = 一个合集都没有，必须先新建）。
class CollectionPickerPage extends ConsumerStatefulWidget {
  final bool firstRun;

  const CollectionPickerPage({super.key, this.firstRun = false});

  @override
  ConsumerState<CollectionPickerPage> createState() =>
      _CollectionPickerPageState();
}

class _CollectionPickerPageState extends ConsumerState<CollectionPickerPage> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('请先给合集起个名字');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(collectionsProvider.notifier).create(name);
      _name.clear();
      _snack('已创建并进入合集「$name」');
    } catch (e) {
      _snack('创建失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter(String id, String name) async {
    await ref.read(collectionsProvider.notifier).select(id);
    if (mounted) _snack('已进入合集「$name」');
  }

  Future<void> _delete(String id, String name, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除合集'),
        content: Text(count == 0
            ? '确定删除合集「$name」？'
            : '合集「$name」下有 $count 条识别记录。\n删除合集不会删掉这些记录，'
                '它们会回到「全部记录」里。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(collectionsProvider.notifier).delete(id);
    if (mounted) _snack('已删除合集「$name」');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 上次使用的合集排首位（用户需求 8 每次打开都要选择，减少误选）。
  static List<Collection> _sorted(
      List<Collection> list, String? lastUsedId) {
    if (lastUsedId == null || lastUsedId.isEmpty) return list;
    final first = <Collection>[];
    final rest = <Collection>[];
    for (final c in list) {
      (c.collectionId == lastUsedId ? first : rest).add(c);
    }
    return [...first, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? '新建任务合集' : '选择任务合集'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              if (widget.firstRun) ...[
                const SectionCard(
                  title: '第一次使用',
                  subtitle: '识别结果都归属于某个「任务合集」，方便以后导出与查找。'
                      '先给这次任务起个名字吧。',
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              SectionCard(
                title: '新建合集',
                subtitle: '例如「期末复习」「第三章作业」',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('collection-name'),
                          controller: _name,
                          autofocus: widget.firstRun,
                          decoration: const InputDecoration(
                            hintText: '合集名称',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _create(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        key: const ValueKey('collection-create'),
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建并进入'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: '已有合集',
                subtitle: '点击进入后，本次的所有识别都会记在这个合集里',
                children: [
                  if (collections.isEmpty)
                    const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: '还没有合集',
                      message: '在上面输入名字新建一个，之后每次打开都可以直接进入。',
                    )
                  else
                    Column(
                      children: [
                        // 上次用的合集排在最前并标出来（每次打开都要重选）。
                        for (final c in _sorted(collections,
                            ref.watch(lastCollectionIdProvider).valueOrNull))
                          _CollectionTile(
                            collectionId: c.collectionId,
                            name: c.name,
                            lastUsed: c.collectionId ==
                                ref.watch(lastCollectionIdProvider).valueOrNull,
                            onEnter: () => _enter(c.collectionId, c.name),
                            onDelete: (count) =>
                                _delete(c.collectionId, c.name, count),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  final String collectionId;
  final String name;
  final bool lastUsed;
  final VoidCallback onEnter;
  final void Function(int count) onDelete;

  const _CollectionTile({
    required this.collectionId,
    required this.name,
    required this.onEnter,
    required this.onDelete,
    this.lastUsed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(collectionSessionCountProvider(collectionId));
    return ListTile(
      key: ValueKey('collection-$collectionId'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.folder_outlined,
            size: 20, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (lastUsed) ...[
            const SizedBox(width: 8),
            StatusPill(label: '上次使用', color: theme.colorScheme.primary),
          ],
        ],
      ),
      subtitle:
          Text(count.when(data: (c) => '$c 条识别记录', loading: () => '…', error: (_, _) => '')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '删除合集',
            onPressed: () => onDelete(count.valueOrNull ?? 0),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
          FilledButton.tonal(onPressed: onEnter, child: const Text('进入')),
        ],
      ),
    );
  }
}

/// 从任意入口（托盘 / 主界面）弹出合集切换。
Future<void> showCollectionPicker(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: const _CollectionPickerDialog(),
      ),    ),
  );
}

class _CollectionPickerDialog extends ConsumerStatefulWidget {
  const _CollectionPickerDialog();

  @override
  ConsumerState<_CollectionPickerDialog> createState() =>
      _CollectionPickerDialogState();
}

class _CollectionPickerDialogState
    extends ConsumerState<_CollectionPickerDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 删除合集（M19 第 2 条）。
  ///
  /// 这个弹窗是**唯一随时可达**的合集入口（顶栏药丸 / 托盘 / 设置页都走它），
  /// 而原来只有启动时的合集选择页能删——用户进去才发现没有删除入口。
  /// 与选择页一致：二次确认、不级联删记录、删掉当前选中的那个就退出选中。
  Future<void> _confirmDelete(Collection c) async {
    final count =
        await ref.read(repoProvider).sessionCountOfCollection(c.collectionId);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除合集'),
        content: Text(count == 0
            ? '确定删除合集「${c.name}」？'
            : '合集「${c.name}」下有 $count 条识别记录。\n删除合集不会删掉这些记录，'
                '它们会回到「全部记录」里。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              key: const ValueKey('picker-delete-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(collectionsProvider.notifier).delete(c.collectionId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已删除合集「${c.name}」')));
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider).valueOrNull ?? const [];
    final activeId = ref.watch(activeCollectionIdProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('切换任务合集', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text('切换后，新的识别会记进所选合集；手机上也会同步看到。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              children: [
                for (final c in collections)
                  ListTile(
                    key: ValueKey('pick-${c.collectionId}'),
                    selected: c.collectionId == activeId,
                    leading: Icon(c.collectionId == activeId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(c.name),
                    trailing: IconButton(
                      key: ValueKey('picker-delete-${c.collectionId}'),
                      tooltip: '删除合集',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _confirmDelete(c),
                    ),
                    onTap: () async {
                      await ref
                          .read(collectionsProvider.notifier)
                          .select(c.collectionId);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('picker-new-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                      hintText: '新建合集名称', isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                onPressed: () async {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  await ref.read(collectionsProvider.notifier).create(name);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('新建并进入'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
