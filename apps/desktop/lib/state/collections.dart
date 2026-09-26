import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'app_scope.dart';

/// 任务合集（用户需求 8）：Windows 首次开始必须新建并选中一个合集，
/// 之后每次打开都要选择；所有识别都落在当前选中的合集里。
///
/// 选中状态存本地设置（`kActiveCollectionKey`，不参与同步），并通过
/// `DesktopServerController` 广播给安卓端（用户需求 12）。
class CollectionController extends StateNotifier<AsyncValue<List<Collection>>> {
  final Ref ref;
  StreamSubscription<List<Collection>>? _sub;

  CollectionController(this.ref) : super(const AsyncValue.loading()) {
    reload();
    _sub = ref.read(repoProvider).watchCollections().listen(
          (list) => state = AsyncValue.data(list),
          onError: (Object e, StackTrace s) => state = AsyncValue.error(e, s),
        );
  }

  Future<void> reload() async {
    try {
      final list = await ref.read(repoProvider).listCollections();
      state = AsyncValue.data(list);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// 新建合集（用户需求 8：首次开始必须命名）。
  Future<Collection> create(String name) async {
    final trimmed = name.trim().isEmpty ? '未命名合集' : name.trim();
    final now = nowMs();
    final repo = ref.read(repoProvider);
    final c = await repo.upsertCollection(Collection(
      collectionId: newUuidV4(),
      name: trimmed,
      createdAt: now,
      updatedAt: now,
      updatedBy: repo.deviceId,
    ));
    await select(c.collectionId);
    return c;
  }

  Future<void> rename(String collectionId, String name) async {
    final repo = ref.read(repoProvider);
    final c = await repo.getCollection(collectionId);
    if (c == null) return;
    await repo.upsertCollection(
        c.copyWith(name: name.trim().isEmpty ? c.name : name.trim()));
  }

  /// 选中合集：写本地设置并通知已连接的安卓端。
  Future<void> select(String collectionId) async {
    final repo = ref.read(repoProvider);
    final c = await repo.getCollection(collectionId);
    if (c == null) return;
    await repo.setSetting(kActiveCollectionKey, collectionId);
    // 记下来供下次启动的选择页标「上次使用」（用户需求 8）。
    await repo.setSetting(kLastCollectionKey, collectionId);
    ref.read(activeCollectionIdProvider.notifier).state = collectionId;
    ref.invalidate(lastCollectionIdProvider);
    await ref.read(serverControllerProvider).notifyCollectionChanged();
  }

  /// 删除合集（不级联删除其下会话，用户仍能从「全部记录」看到它们）。
  Future<void> delete(String collectionId) async {
    final repo = ref.read(repoProvider);
    await repo.deleteCollection(collectionId);
    final active = ref.read(activeCollectionIdProvider);
    if (active == collectionId) {
      await repo.setSetting(kActiveCollectionKey, '');
      ref.read(activeCollectionIdProvider.notifier).state = null;
      await ref.read(serverControllerProvider).notifyCollectionChanged();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// 全部合集（时间倒序）。
final collectionsProvider =
    StateNotifierProvider<CollectionController, AsyncValue<List<Collection>>>(
        (ref) => CollectionController(ref));

/// 当前选中的合集 id（null = 还没选，UI 必须挡在合集选择页）。
final activeCollectionIdProvider = StateProvider<String?>((ref) => null);

/// 当前选中的合集对象。
final activeCollectionProvider = Provider<Collection?>((ref) {
  final id = ref.watch(activeCollectionIdProvider);
  final list = ref.watch(collectionsProvider).valueOrNull ?? const [];
  if (id == null) return null;
  for (final c in list) {
    if (c.collectionId == id) return c;
  }
  return null;
});

/// 上次用过的合集 id（用户需求 8：每次打开都要重选，选择页把它标出来并排首位）。
final lastCollectionIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(repoProvider).getSetting(kLastCollectionKey);
});

/// 某个合集下的会话（时间倒序）。
final collectionSessionsProvider =
    StreamProvider.family<List<Session>, String?>((ref, collectionId) {
  return ref.watch(repoProvider).watchSessions(collectionId: collectionId);
});

/// 某个合集的识别记录数（合集列表展示用）。
final collectionSessionCountProvider =
    FutureProvider.family.autoDispose<int, String>((ref, collectionId) {
  return ref.watch(repoProvider).sessionCountOfCollection(collectionId);
});
