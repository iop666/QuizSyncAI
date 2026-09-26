import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/shell_open.dart';
import '../state/analysis_workflow.dart' show WorkflowResult;
import '../state/app_scope.dart';
import '../state/capture_coordinator.dart'
    show decodeImage, imageFileReader, loadSessionFirstImage, CaptureCoordinator;
import '../state/collections.dart';
import 'collection_export.dart';
import 'collection_picker_page.dart';
import 'crop_retry_dialog.dart';

import 'settings_page.dart';

/// 主窗口（SPEC 2.2）：左侧会话列表、右侧当前会话内容、底部导航。
/// M8：整体排版改为「侧栏卡片列表 + 内容头 + 卡片题目 + 底部导航条」。
class HomePage extends ConsumerStatefulWidget {
  /// 「截屏搜题」入口（由外壳注入协调器；只 pump 页面时为 null）。
  final Future<void> Function()? onCapture;

  /// 采集协调器（用户需求 4）：主界面据此显示多页暂存进度、
  /// 在识别完成后跳转到新会话。只 pump 页面做布局测试时为 null。
  final CaptureCoordinator? coordinator;

  const HomePage({super.key, this.onCapture, this.coordinator});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

/// 侧栏数据源：默认只看**当前选中的合集**（用户需求 8）；
/// 切到「全部记录」或还没选合集时回退到全部会话。
final sidebarAllSessionsProvider = StateProvider<bool>((ref) => false);

final sidebarSessionsProvider = StreamProvider<List<Session>>((ref) {
  final all = ref.watch(sidebarAllSessionsProvider);
  final collectionId = ref.watch(activeCollectionIdProvider);
  final repo = ref.watch(repoProvider);
  if (all || collectionId == null) return repo.watchSessions();
  return repo.watchSessions(collectionId: collectionId);
});

/// 多页暂存区里的页数（协调器 `onStagingChanged` 推到这里；widget 测试可 override）。
final stagedPageCountProvider = StateProvider<int>((ref) => 0);

/// 会话的页数（用户需求 4）：>1 时侧栏给出「N 页」标记。
final sessionPageCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, sessionId) async {
  final hashes = await ref.watch(repoProvider).imageHashesOf(sessionId);
  return hashes.length;
});

class _HomePageState extends ConsumerState<HomePage> {
  SessionNav _nav = SessionNav(const []);
  ValueNotifier<String?>? _remoteTask;

  /// 识别完成后要跳过去的新会话 id：新会话可能还没进侧栏流，等它出现再跳。
  String? _pendingJumpId;

  @override
  void initState() {
    super.initState();
    final initial =
        ref.read(sidebarSessionsProvider).value ?? const <Session>[];
    _nav = SessionNav(initial);
    final coordinator = widget.coordinator;
    if (coordinator != null) {
      coordinator.onStagingChanged = _onStagingChanged;
      coordinator.onSessionReady = _jumpToSession;
    }
    // 用户反馈 12：手机发起的识别也要在 Windows 端「显示识别界面」。
    _remoteTask = ref.read(remoteTaskSessionProvider);
    _remoteTask!.addListener(_onRemoteTaskChanged);
    _consumeRemoteTask();
    ref.listenManual(sidebarSessionsProvider, (prev, next) {
      // 切换数据源（当前合集 ⇄ 全部记录）时会短暂 loading：保留当前列表，
      // 否则侧栏会闪一下空白并把「本次」重置掉。
      if (!next.hasValue) return;
      final sessions = next.requireValue;
      // 「本次」始终指向最新一条；**只有用户正在翻旧会话时**才保留当前位置。
      // 原来无条件保留当前会话，导致截屏产生新会话后界面仍停在旧记录上
      // （看不到「识别中」与新结果，必须手动点「回到本次」）。
      final keepId = _nav.isAtLatest ? null : _nav.current?.sessionId;
      _nav = SessionNav(sessions);
      if (keepId != null) {
        _nav.jumpTo(keepId);
      }
      final pending = _pendingJumpId;
      if (pending != null && sessions.any((s) => s.sessionId == pending)) {
        _pendingJumpId = null;
        _nav.jumpTo(pending);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    final coordinator = widget.coordinator;
    if (coordinator != null) {
      coordinator.onStagingChanged = null;
      coordinator.onSessionReady = null;
    }
    _remoteTask?.removeListener(_onRemoteTaskChanged);
    super.dispose();
  }

  /// 手机发起了识别（用户反馈 12）：把右侧切到那次识别的会话。
  void _onRemoteTaskChanged() => _consumeRemoteTask();

  void _consumeRemoteTask() {
    final id = _remoteTask?.value;
    if (id == null || id.isEmpty) return;
    _remoteTask!.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpToSession(id);
    });
  }

  /// 多页暂存页数变化（协调器在每次追加/清空/上传后回调）。
  void _onStagingChanged() {
    if (!mounted) return;
    final count = widget.coordinator?.stagedCount ?? 0;
    if (ref.read(stagedPageCountProvider) != count) {
      ref.read(stagedPageCountProvider.notifier).state = count;
    }
  }

  /// 识别完成 → 跳到新会话（用户需求 2/4：做完就能立刻看到结果）。
  void _jumpToSession(String sessionId) {
    if (!mounted) return;
    setState(() {
      if (_nav.sessions.any((s) => s.sessionId == sessionId)) {
        _nav.jumpTo(sessionId);
      } else {
        _pendingJumpId = sessionId;
      }
    });
  }

  void _clearStaging() {
    final coordinator = widget.coordinator;
    if (coordinator != null) {
      // 协调器负责提示与 onStagingChanged 回调。
      coordinator.clearStaging();
      return;
    }
    // 只 pump 页面（无协调器）时仍要有反馈：本地清零 + 提示。
    ref.read(stagedPageCountProvider.notifier).state = 0;
    _toast('已清空多页暂存区');
  }

  @override
  Widget build(BuildContext context) {
    final sessions =
        ref.watch(sidebarSessionsProvider).valueOrNull ?? const <Session>[];
    // 切换合集/范围时列表会短暂 loading：此时不要把上一个合集的记录留在右侧，
    // 否则会有一瞬间看到不属于当前合集的题目。
    final current = _nav.current;
    final session = (current != null &&
            sessions.any((s) => s.sessionId == current.sessionId))
        ? current
        : null;
    final activeCollection = ref.watch(activeCollectionProvider);
    final showAll = ref.watch(sidebarAllSessionsProvider);
    final stagedCount = ref.watch(stagedPageCountProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const _Logo(),
            const SizedBox(width: 10),
            const Text('QuizSync AI'),
            const SizedBox(width: 12),
            Flexible(
              child: _CollectionPill(
                collection: activeCollection,
                showAll: showAll,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: _HotkeyPill()),
          ],
        ),
        actions: [
          if (activeCollection != null)
            IconButton(
              key: const ValueKey('export-collection'),
              tooltip: '导出当前合集（Markdown + JSON）',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => exportCollection(
                context,
                ref,
                collection: activeCollection,
                dataRoot: ref.read(dataRootProvider),
              ),
            ),
          _SearchButton(
            onPicked: (sessionId) => setState(() => _nav.jumpTo(sessionId)),
          ),
          const _SettingsButton(),
          const SizedBox(width: 10),
        ],
      ),
      body: Listener(
        // Ctrl + 滚轮实时缩放字号（SPEC 4.1）。
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final pressed = HardwareKeyboard.instance.logicalKeysPressed;
            final ctrl = pressed.any((k) =>
                k == LogicalKeyboardKey.controlLeft ||
                k == LogicalKeyboardKey.controlRight);
            if (ctrl) {
              final delta = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
              ref.read(settingsProvider).adjustFontSize(delta);
            }
          }
        },
        child: Column(
          children: [
            // 用户反馈 5：多页暂存条**只有真正在攒页时才显示**，
            // 默认（暂存 0 页）整条不出现，主界面保持干净。
            if (stagedCount > 0)
              _StagingBar(stagedCount: stagedCount, onClear: _clearStaging),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 296,
                    child: _SessionSidebar(
                      sessions: sessions,
                      selectedId: session?.sessionId,
                      showAll: showAll,
                      collectionName: activeCollection?.name,
                      onSelect: (id) => setState(() => _nav.jumpTo(id)),
                      onRetry: _onRetry,
                      onNewCapture: widget.onCapture,
                    ),
                  ),
                  VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).dividerColor),
                  Expanded(
                      child: _ContentPane(
                    session: session,
                    nav: _nav,
                    onNavChanged: () => setState(() {}),
                    onRetry: _onRetry,
                    onCropRetry: _onCropRetry,
                    onOpenSettings: _openSettings,
                    onCapture: widget.onCapture,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Future<void> _onRetry(Session session) async {
    final workflow = ref.read(workflowProvider);
    final settings = ref.read(settingsProvider);
    final apiKey = await ref.read(apiKeyReaderProvider)();
    final jpeg = await _loadSessionImage(session);
    if (!mounted) return;
    if (jpeg == null) {
      _toast('原始截图文件不存在，无法重试（可在设置开启「保存图片」）');
      return;
    }
    // 多页会话要读回**全部**页：缺少任何一页时 retrySession 会抛 StateError，
    // 这里必须把它的原话显示出来（不能吞掉，否则用户只看到「没反应」）。
    final imageDir = '${ref.read(dataRootProvider)}/images';
    workflow.readImageFile = imageFileReader(imageDir);
    final WorkflowResult result;
    try {
      result = await workflow.retrySession(
        sessionId: session.sessionId,
        jpeg: jpeg,
        config: AiConfig(
          providerId: settings.ai.providerId,
          baseUrl: settings.ai.baseUrl,
          apiKey: apiKey ?? '',
          model: settings.ai.model,
          timeoutSeconds: settings.ai.timeoutSeconds,
        ),
      );
    } on StateError catch (e) {
      _toast(e.message);
      return;
    } catch (e) {
      _toast('重新分析失败：$e');
      return;
    }
    if (!mounted) return;
    setState(() => _nav.jumpTo(result.sessionId));
    if (result.message != null) _toast(result.message!);
    if (!result.ok && result.errorMessage != null) _toast(result.errorMessage!);
  }

  /// 手动框选重试（SPEC §8：仅「未识别到题目」时临时启用）。
  Future<void> _onCropRetry(Session session) async {
    final jpeg = await _loadSessionImage(session);
    if (!mounted) return;
    if (jpeg == null) {
      _toast('原始截图文件不存在，无法框选（可在设置开启「保存图片」）');
      return;
    }
    final decoded = decodeImage(jpeg);
    if (decoded == null) {
      _toast('截图解码失败');
      return;
    }
    final rect = await showCropRetryDialog(
      context,
      jpegBytes: jpeg,
      imageWidth: decoded.width,
      imageHeight: decoded.height,
    );
    if (rect == null || !mounted) return;
    final cropped = ImageProc.cropToJpeg(
      decoded.bgra, decoded.width, decoded.height,
      rect.x1, rect.y1, rect.x2, rect.y2,
    );
    final workflow = ref.read(workflowProvider);
    final settings = ref.read(settingsProvider);
    final apiKey = await ref.read(apiKeyReaderProvider)();
    if (!mounted) return;
    final result = await workflow.run(
      jpeg: cropped.jpeg,
      imageHash: sha256Hex(cropped.jpeg),
      width: cropped.width,
      height: cropped.height,
      config: AiConfig(
        providerId: settings.ai.providerId,
        baseUrl: settings.ai.baseUrl,
        apiKey: apiKey ?? '',
        model: settings.ai.model,
        timeoutSeconds: settings.ai.timeoutSeconds,
      ),
    );
    if (!mounted) return;
    setState(() => _nav.jumpTo(result.sessionId));
    if (result.message != null) _toast(result.message!);
    if (!result.ok && result.errorMessage != null) _toast(result.errorMessage!);
  }

  Future<Uint8List?> _loadSessionImage(Session session) =>
      loadSessionFirstImage(ref.read(repoProvider), session);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 顶栏品牌标记：直接显示**应用自己的图标**。
///
/// 用户反馈 8：这里原来是自绘的渐变方块 + 放大镜，跟任务栏/安装包上的
/// 那枚图标不是同一张图，用户认不出「QuizSync AI」前面这个是软件图标。
/// 现在复用关于页同一份资源 `assets/app_icon.png`（由 `tool/make_icons.dart`
/// 从 `icon/QuizSync_AI.png` 生成，自带圆角与透明边），不新造图片。
class _Logo extends StatelessWidget {
  const _Logo();

  /// 与标题字号同一视觉重量；固定宽高，图片不会被拉变形。
  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: const ValueKey('app-title-logo'),
      // 图标本身已带圆角，这里再裁一次是兜底：换图也不会露出直角。
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        'assets/app_icon.png',
        key: const ValueKey('app-title-logo-image'),
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// 顶栏合集药丸（用户需求 8）：显示当前任务合集，点击弹出合集切换。
class _CollectionPill extends ConsumerWidget {
  final Collection? collection;
  final bool showAll;

  const _CollectionPill({required this.collection, required this.showAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = collection?.name ?? '未选择合集';
    final label = showAll && collection != null ? '$name · 全部记录' : name;
    final color = collection == null
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Tooltip(
      message: '当前任务合集：$name（点击切换）',
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          key: const ValueKey('collection-pill'),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: () => showCollectionPicker(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    showAll
                        ? Icons.folder_copy_outlined
                        : Icons.folder_outlined,
                    size: 13,
                    color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 15, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 多页识别暂存条（用户需求 4；用户反馈 5：只在攒页时出现）：
/// 页数进度 + 两个真实热键 + 清空入口。暂存 0 页时整条不渲染。
class _StagingBar extends ConsumerWidget {
  final int stagedCount;
  final VoidCallback onClear;

  const _StagingBar({required this.stagedCount, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final limit = ref.watch(settingsProvider).app.multiPageLimit;
    final multipage = ref.watch(activeMultipageHotkeyProvider);
    final finish = ref.watch(activeHotkeyProvider);
    final full = limit > 0 && stagedCount >= limit;

    final String hint;
    if (stagedCount == 0) {
      hint = '按「多页模式」热键开始攒页；抓满 $limit 张会自动上传识别';
    } else if (full) {
      hint = '已抓满 $limit 张，正在自动上传识别；也可以按「截屏识别」立刻上传';
    } else {
      hint = '继续按「多页模式」加页；抓满 $limit 张自动上传，'
          '或按「截屏识别」结束多页立刻上传';
    }

    final active = stagedCount > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 5, 12, 5),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary.withValues(alpha: 0.07)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_outlined,
                  size: 15,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                '多页暂存：$stagedCount/$limit 页',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
          Text(
            hint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          _HotkeyChip(label: '多页模式', value: multipage),
          _HotkeyChip(label: '结束多页', value: finish),
          TextButton.icon(
            key: const ValueKey('clear-staging'),
            onPressed: stagedCount == 0 ? null : onClear,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.layers_clear_outlined, size: 16),
            label: const Text('清空暂存区'),
          ),
        ],
      ),
    );
  }
}

/// 只读热键提示：null 表示候选键都被其他程序占用（不能写死按键名）。
class _HotkeyChip extends StatelessWidget {
  final String label;
  final String? value;

  const _HotkeyChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = value == null;
    return Text(
      taken ? '$label：热键被占用，可从托盘菜单操作' : '$label：$value',
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 11,
        color: taken
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 顶栏热键提示药丸。
class _HotkeyPill extends ConsumerWidget {
  const _HotkeyPill();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hk = ref.watch(activeHotkeyProvider);
    return StatusPill(
      icon: Icons.keyboard_outlined,
      label: hk ?? '无可用热键',
      color: hk == null
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
      filled: false,
    );
  }
}

/// 顶栏的配对状态药丸（M19 第 1 条 → M21 第 2 条**按用户要求删除**）。
///
/// 用户先要求把「服务 8765 · 0 台」改成配对状态（`已配对设备：安卓设备` /
/// `未配对`），随后又说「删除掉『未配对』和已配对那个药丸显示」—— 顶栏不再有
/// 这一枚药丸。服务端口与已配对设备仍可在「设置 → 连接设备」里逐台看到。
/// `CoreRepository.watchDevices()` 保留（它是一条有真服务端集成测试的
/// 库变更流，连接设备页以后可以直接用它替掉手动刷新的 `tick`）。

/// 缩略图：有本地文件就显示真图，否则显示占位。
///
/// 用户反馈 M15 第 2 条：`images.local_path` 为空时**回落到约定路径**
/// `<数据目录>/images/<hash>.jpg`。手机上传的图以前根本不写 local_path
/// （服务端先写文件、后查库，查到的永远是 null），于是 Windows 主界面对手机
/// 传来的记录一直显示占位图标；回落既修好了历史数据，也让「库里有记录、
/// 文件就在盘上」这种情况自愈。
final _thumbProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, hash) async {
  final meta = await ref.watch(repoProvider).getImage(hash);
  final path = meta?.localPath;
  if (path != null && File(path).existsSync()) return path;
  final fallback = '${ref.watch(dataRootProvider)}/images/$hash.jpg';
  return File(fallback).existsSync() ? fallback : null;
});

class _SearchButton extends ConsumerWidget {
  final void Function(String sessionId) onPicked;

  const _SearchButton({required this.onPicked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: '搜索历史题目（题干 / 解析）',
      icon: const Icon(Icons.search),
      onPressed: () async {
        final hit = await showSearch<String>(
            context: context, delegate: _QuestionSearchDelegate(ref));
        // 原来没有接返回值：点搜索结果只是关掉搜索框，什么都不发生。
        if (hit == null || hit.isEmpty) return;
        onPicked(hit);
      },
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '设置',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
    );
  }
}

/// 左侧历史记录侧栏（用户需求 8）：默认只显示**当前合集**的识别记录，
/// 可以一键切到「全部记录」。
class _SessionSidebar extends ConsumerWidget {
  final List<Session> sessions;
  final String? selectedId;
  final bool showAll;
  final String? collectionName;
  final void Function(String sessionId) onSelect;
  final void Function(Session session) onRetry;
  final Future<void> Function()? onNewCapture;

  const _SessionSidebar({
    required this.sessions,
    required this.selectedId,
    required this.showAll,
    required this.collectionName,
    required this.onSelect,
    required this.onRetry,
    required this.onNewCapture,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hotkey = ref.watch(activeHotkeyProvider) ?? '全局热键';
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('历史记录',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                StatusPill(
                  label: '${sessions.length}',
                  color: theme.colorScheme.onSurfaceVariant,
                  filled: false,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<bool>(
              key: const ValueKey('sidebar-scope'),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(theme.textTheme.bodySmall),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('当前合集')),
                ButtonSegment(value: true, label: Text('全部记录')),
              ],
              selected: {showAll},
              onSelectionChanged: (v) => ref
                  .read(sidebarAllSessionsProvider.notifier)
                  .state = v.first,
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? (showAll
                    ? EmptyState(
                        icon: Icons.history_toggle_off,
                        title: '还没有识别记录',
                        message: '按 $hotkey 截屏搜题，\n或把图片直接拖进窗口。',
                      )
                    // 空状态要能区分「这个合集还没记录」与「搜索没匹配」。
                    : EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: '这个合集还没有记录',
                        message: collectionName == null
                            ? '按 $hotkey 截屏搜题，结果会记进当前合集。'
                            : '按 $hotkey 截屏搜题，结果会记进「$collectionName」。\n'
                                '也可以切到「全部记录」看看以前搜过的。',
                      ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) => _SessionTile(
                      session: sessions[i],
                      selected: sessions[i].sessionId == selectedId,
                      onTap: () => onSelect(sessions[i].sessionId),
                      onRetry: () => onRetry(sessions[i]),
                    ),
                  ),
          ),
          if (sessions.isNotEmpty && onNewCapture != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: OutlinedButton.icon(
                onPressed: () => onNewCapture!(),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('截屏搜题'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Session session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final style = statusStyle(session.status.wire, dark: dark);
    final thumb = ref.watch(_thumbProvider(session.imageHash));
    // 多页会话（用户需求 4）：侧栏一眼看出这条是几页拼起来的一次识别。
    final pageCount =
        ref.watch(sessionPageCountProvider(session.sessionId)).valueOrNull ?? 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: dark ? 0.16 : 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _thumbnail(context, thumb.valueOrNull, style),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline(session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: session.status == TaskState.failed
                              ? style.color
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: style.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${_time(session)} · ${style.label} · '
                              '${session.sourceDevice == 'windows-local' ? '本机' : '手机'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          if (pageCount > 1) ...[
                            const SizedBox(width: 4),
                            StatusPill(
                              label: '$pageCount 页',
                              color: theme.colorScheme.onSurfaceVariant,
                              filled: false,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (session.status == TaskState.failed)
                  IconButton(
                    tooltip: '重新分析',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: onRetry,
                  )
                else if (session.status == TaskState.analyzing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(
      BuildContext context, String? path, ({Color color, IconData icon, String label}) style) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 54,
        height: 42,
        color: theme.colorScheme.surfaceContainerHighest,
        child: path == null
            ? Icon(style.icon,
                size: 18, color: style.color.withValues(alpha: 0.8))
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 108,
                errorBuilder: (_, _, _) => Icon(style.icon,
                    size: 18, color: style.color.withValues(alpha: 0.8)),
              ),
      ),
    );
  }

  /// 首行：优先显示题目数/失败原因，一眼能分辨。
  String _headline(Session s) {
    if (s.status == TaskState.failed) {
      return '识别失败：${s.errorMessage ?? _errorLabel(s.errorCode)}';
    }
    if (s.status == TaskState.analyzing) return '正在识别…';
    if (s.status == TaskState.queued) return '排队中…';
    if (s.status == TaskState.cancelled) return '已取消';
    return s.questionCount == 0 ? '未识别到题目' : '识别出 ${s.questionCount} 道题';
  }

  String _errorLabel(String? code) => switch (code) {
        'ai_timeout' => 'AI 超时',
        'ai_auth' => 'API Key 无效',
        'ai_rate_limited' => '触发限流',
        'ai_bad_response' => 'AI 返回无法解析',
        'ai_quota_exceeded' => '今日调用已达上限',
        'no_question_found' => '未识别到题目',
        _ => code ?? '分析失败',
      };

  String _time(Session s) {
    final t = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
    return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// 右侧内容：会话头 + 题目卡片纵向滚动 + 底部导航。
class _ContentPane extends ConsumerWidget {
  final Session? session;
  final SessionNav nav;
  final VoidCallback onNavChanged;
  final void Function(Session session) onRetry;
  final Future<void> Function(Session session) onCropRetry;
  final VoidCallback onOpenSettings;
  final Future<void> Function()? onCapture;

  const _ContentPane({
    required this.session,
    required this.nav,
    required this.onNavChanged,
    required this.onRetry,
    required this.onCropRetry,
    required this.onOpenSettings,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session == null) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.document_scanner_outlined,
              title: '准备好搜题了',
              message:
                  '按 ${ref.watch(activeHotkeyProvider) ?? '（热键被其他程序占用，可在设置页更换）'} 截屏，\n'
                  '或用 Win+Shift+S 截图（自动识别）、Ctrl+V 粘贴、把图片拖进窗口。',
              actions: [
                if (onCapture != null)
                  FilledButton.icon(
                    onPressed: () => onCapture!(),
                    icon: const Icon(Icons.screenshot_monitor, size: 18),
                    label: const Text('立即截屏搜题'),
                  ),
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('打开设置'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _Footer(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      );
    }
    final s = session!;
    final settings = ref.watch(settingsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = statusStyle(s.status.wire, dark: dark);

    return Column(
      children: [
        _header(context, ref, s, style),
        const Divider(height: 1),
        Expanded(
          child: s.status == TaskState.analyzing
              ? _AnalyzingPane(session: s)
              : _QuestionsPane(
                  session: s,
                  fontSize: settings.app.fontSize,
                  onCropRetry: onCropRetry,
                  onRetry: onRetry,
                ),
        ),
        const Divider(height: 1),
        _navBar(context),
      ],
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, Session s,
      ({Color color, IconData icon, String label}) style) {
    final theme = Theme.of(context);
    final t = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
    String two(int v) => v.toString().padLeft(2, '0');
    // 窄窗口（最小 860 窗口 - 296 侧栏）时把工具按钮收进「更多」，
    // 否则这一行会横向溢出（黄黑条）。
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${t.year}-${two(t.month)}-${two(t.day)} '
                        '${two(t.hour)}:${two(t.minute)}',
                        style: theme.textTheme.titleMedium,
                      ),
                      StatusPill(
                        icon: style.icon,
                        label: style.label,
                        color: style.color,
                      ),
                      StatusPill(
                        label: s.sourceDevice == 'windows-local' ? '本机' : '手机',
                        color: theme.colorScheme.onSurfaceVariant,
                        filled: false,
                      ),
                      if (s.questionCount > 0)
                        StatusPill(
                          label: '${s.questionCount} 题',
                          color: theme.colorScheme.onSurfaceVariant,
                          filled: false,
                        ),
                      if (s.latencyMs != null && s.latencyMs! > 0)
                        StatusPill(
                          label: '${(s.latencyMs! / 1000).toStringAsFixed(1)}s',
                          color: theme.colorScheme.onSurfaceVariant,
                          filled: false,
                        ),
                    ],
                  ),
                  if (s.aiModel != null && s.aiModel!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('模型 ${s.aiModel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (compact)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => _runAction(context, ref, s, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'retry', child: Text('重新分析')),
                  PopupMenuItem(value: 'copy', child: Text('复制全部')),
                  PopupMenuItem(value: 'export', child: Text('导出本次（Markdown）')),
                  PopupMenuItem(value: 'delete', child: Text('删除本次')),
                ],
              )
            else ...[
              IconButton(
                tooltip: '重新分析（重新调用 AI）',
                icon: const Icon(Icons.refresh),
                onPressed: () => onRetry(s),
              ),
              IconButton(
                tooltip: '复制全部题目与答案',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () => _copyAll(context, ref, s),
              ),
              IconButton(
                tooltip: '导出本次（Markdown）',
                icon: const Icon(Icons.ios_share_outlined),
                onPressed: () => _exportSession(context, ref, s),
              ),
              IconButton(
                tooltip: '删除本次',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteSession(context, ref, s),
              ),
            ],
          ],
        ),
      );
    });
  }

  void _runAction(BuildContext context, WidgetRef ref, Session s, String action) {
    switch (action) {
      case 'retry':
        onRetry(s);
      case 'copy':
        _copyAll(context, ref, s);
      case 'export':
        _exportSession(context, ref, s);
      case 'delete':
        _deleteSession(context, ref, s);
    }
  }

  /// 删除要二次确认，并且给出反馈（原来点一下就直接没了，无提示）。
  Future<void> _deleteSession(
      BuildContext context, WidgetRef ref, Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后不会出现在历史列表里（软删除，30 天后彻底清理）。'),
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
    await ref.read(repoProvider).deleteSession(s.sessionId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除该条记录')));
    }
  }

  Future<void> _exportSession(
      BuildContext context, WidgetRef ref, Session s) async {
    try {
      final questions =
          await ref.read(repoProvider).questionsOfSession(s.sessionId);
      final md = Exporter.sessionToMarkdown(s, questions);
      final dir = Directory('${_dataRoot(ref)}/exports');
      await dir.create(recursive: true);
      final t = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
      // 用户反馈 2：导出时弹「另存为」，默认目录是软件数据目录。
      final chosen = savePathChooser(
        title: '导出本次识别（Markdown）',
        defaultDir: dir.path,
        defaultName: 'session-${t.month}${t.day}-${s.sessionId.substring(0, 6)}.md',
        extension: 'md',
        filterLabel: 'Markdown',
      );
      if (chosen == null) return;
      final file = File(chosen);
      await file.parent.create(recursive: true);
      await file.writeAsString(md);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导出：${file.path}'),
          action: SnackBarAction(
            label: '打开所在目录',
            onPressed: () => revealFolder(file.parent.path),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  String _dataRoot(WidgetRef ref) {
    // 与 main.dart 的 dataDir 约定一致（%APPDATA%/…/quizsync 由 path_provider 决定）。
    return ref.read(dataRootProvider);
  }

  Future<void> _copyAll(BuildContext context, WidgetRef ref, Session s) async {
    final questions =
        await ref.read(repoProvider).questionsOfSession(s.sessionId);
    if (questions.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这次识别没有题目可复制')));
      }
      return;
    }
    final buf = StringBuffer();
    for (final q in questions) {
      buf.writeln('【${q.questionNo ?? q.ordinal + 1}】${q.stem}');
      for (final o in q.options) {
        buf.writeln('${o.label}. ${o.text}');
      }
      if (q.choice.isNotEmpty) buf.writeln('答案：${q.choice.join('、')}');
      if (q.answerText != null && q.answerText!.isNotEmpty) {
        buf.writeln('答案：${q.answerText}');
      }
      if (q.analysis.isNotEmpty) buf.writeln('解析：${q.analysis}');
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制 ${questions.length} 道题')));
    }
  }

  Widget _navBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          TextButton.icon(
            key: const ValueKey('nav-prev'),
            onPressed: nav.canGoPrev
                ? () {
                    nav.goPrev();
                    onNavChanged();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('上一次'),
          ),
          Text(nav.positionLabel, key: const ValueKey('nav-position')),
          TextButton.icon(
            key: const ValueKey('nav-next'),
            onPressed: nav.canGoNext
                ? () {
                    nav.goNext();
                    onNavChanged();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('下一次'),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('nav-back-latest'),
            onPressed: nav.isAtLatest
                ? null
                : () {
                    nav.backToLatest();
                    onNavChanged();
                  },
            child: const Text('回到本次'),
          ),
          const Spacer(),
          // 窗口拉到最小宽度时免责声明必须能被压缩省略（SPEC 4.4 常驻可见）。
          const Flexible(child: Disclaimer()),
        ],
      ),
    );
  }
}

/// 底部免责声明条（SPEC 4.4：全应用必须存在一处）。
class Disclaimer extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const Disclaimer({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline,
              size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '答案由 AI 生成，仅供参考',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const _Footer({required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Disclaimer(padding: padding),
    );
  }
}

/// 分析中：卡片式进度 + 已耗时 + 取消（SPEC 2.2）。
class _AnalyzingPane extends ConsumerStatefulWidget {
  final Session session;
  const _AnalyzingPane({required this.session});

  @override
  ConsumerState<_AnalyzingPane> createState() => _AnalyzingPaneState();
}

class _AnalyzingPaneState extends ConsumerState<_AnalyzingPane> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeout = ref.watch(settingsProvider).ai.timeoutSeconds;
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text('正在识别题目…', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '已耗时 ${formatSeconds(_seconds)}（超时上限 ${formatSeconds(timeout)}）',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '截图已上传，AI 正在读题并给出答案与解析',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  final container = ProviderScope.containerOf(context);
                  final repo = container.read(repoProvider);
                  final s = await repo.getSession(widget.session.sessionId,
                      includeDeleted: true);
                  if (s != null) {
                    await repo.upsertSession(
                        s.copyWith(status: TaskState.cancelled));
                  }
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 题目卡片纵向滚动（一个会话多题在同一页滚动，SPEC 第 5 节）。
class _QuestionsPane extends ConsumerWidget {
  final Session session;
  final double fontSize;
  final Future<void> Function(Session session) onCropRetry;
  final void Function(Session session) onRetry;

  const _QuestionsPane({
    required this.session,
    required this.fontSize,
    required this.onCropRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionsProvider(session.sessionId));
    return questionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('加载失败：$e')),
      data: (questions) {
        if (questions.isEmpty) {
          if (session.status == TaskState.failed) {
            return _FailedPane(session: session, onCropRetry: onCropRetry, onRetry: onRetry);
          }
          return EmptyState(
            icon: Icons.search_off,
            title: session.status == TaskState.cancelled
                ? '这次识别已取消'
                : '本次没有识别到题目',
            message: '可以换张更清晰的截图，或框选题目区域后重新识别。',
            actions: [
              OutlinedButton.icon(
                onPressed: () => onRetry(session),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新分析'),
              ),
              FilledButton.icon(
                onPressed: () => onCropRetry(session),
                icon: const Icon(Icons.crop_free, size: 18),
                label: const Text('框选后重试'),
              ),
            ],
          );
        }
        // 用户反馈 1：题目正文字重可调（题干单独给，其余文字靠卡片内的
        // DefaultTextStyle 继承）。
        final weight = ref.watch(settingsProvider).app.questionFontWeight;
        return ListView.builder(
          key: const ValueKey('questions-scroll'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: questions.length,
          itemBuilder: (context, i) => QuestionCard(
              question: questions[i],
              fontSize: fontSize,
              fontWeight: weight),
        );
      },
    );
  }
}

/// 失败会话：错误原因 + 可展开的原始返回 + 可行动作（SPEC §8）。
/// 注意：原来这个面板拿了 onCropRetry 却**没有任何按钮**，
/// 「框选题目区域后重试」这个入口在界面上根本点不到。
class _FailedPane extends StatefulWidget {
  final Session session;
  final Future<void> Function(Session session) onCropRetry;
  final void Function(Session session) onRetry;

  const _FailedPane({
    required this.session,
    required this.onCropRetry,
    required this.onRetry,
  });

  @override
  State<_FailedPane> createState() => _FailedPaneState();
}

class _FailedPaneState extends State<_FailedPane> {
  bool _showRaw = false;

  static const _reasons = {
    'ai_timeout': 'AI 请求超时：模型可能太慢，可在设置里调大超时或换更快的模型',
    'ai_auth': 'API Key 无效或无权限：检查设置里的 Key 与模型名是否配套',
    'ai_rate_limited': '触发限流：稍等重试，或在设置里调低每日上限',
    'ai_bad_response': 'AI 返回无法解析：可重试，或换一个更强的模型',
    'ai_quota_exceeded': '今日调用已达上限：可在设置里调整上限',
    'no_question_found': '未识别到题目：可框选题目区域后重试',
    'internal': '内部错误或无法连接 AI 服务',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final reason = _reasons[s.errorCode] ?? s.errorMessage ?? '分析失败';
    // 「未识别到题目」时框选重试最有用；解析失败/超时也允许。
    final canCrop = s.errorCode == 'no_question_found' ||
        s.errorCode == 'ai_bad_response' ||
        s.errorCode == 'ai_timeout' ||
        s.errorCode == null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.error_outline,
                            color: theme.colorScheme.error),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('识别失败',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              s.errorCode == null ? '分析失败' : s.errorCode!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(reason, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: () => widget.onRetry(s),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重新分析'),
                      ),
                      if (canCrop)
                        OutlinedButton.icon(
                          onPressed: () => widget.onCropRetry(s),
                          icon: const Icon(Icons.crop_free, size: 18),
                          label: const Text('框选题目区域后重试'),
                        ),
                      if (s.rawResponse != null)
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showRaw = !_showRaw),
                          icon: Icon(
                              _showRaw
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18),
                          label: Text(_showRaw ? '收起原始返回' : '查看原始返回'),
                        ),
                    ],
                  ),
                  if (_showRaw && s.rawResponse != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(AppRadius.control),
                      ),
                      child: SelectableText(
                        s.rawResponse!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 数据根目录 provider（main 注入；与 db/图片/备份目录同根）。
final dataRootProvider = Provider<String>(
    (ref) => throw UnimplementedError('dataRootProvider must be overridden'));

/// 题目全文搜索（FTS5，排除软删除；SPEC 第 5 节）。
class _QuestionSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;

  _QuestionSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _build(context);

  @override
  Widget buildSuggestions(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const EmptyState(
        icon: Icons.manage_search,
        title: '输入关键词搜索历史',
        message: '会在所有识别过的题干与解析里查找；中文支持 3 字以上子串匹配。',
      );
    }
    return FutureBuilder<List<Question>>(
      future: ref.read(repoProvider).searchQuestions(trimmed),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final hits = snap.data ?? const <Question>[];
        if (hits.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: '没有匹配的记录',
            message: '换个关键词试试（至少 3 个字更准）。',
          );
        }
        return ListView.builder(
          itemCount: hits.length,
          itemBuilder: (context, i) {
            final q = hits[i];
            return ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(q.stem, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('第 ${q.ordinal + 1} 题',
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => close(context, q.sessionId),
            );
          },
        );
      },
    );
  }
}
