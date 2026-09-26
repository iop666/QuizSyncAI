import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../services/live_updates.dart'
    show hostErrorMessage, isNoActiveCollection;
import '../state/providers.dart';
import 'home_page.dart' show Disclaimer;
import 'next_round_banner.dart';
import 'session_tile.dart' show timeLabel;

/// 结果页上那条「电脑正在识别中 / 识别完成」悬浮窗的底色不透明度
/// （M18 第 3 条：用户要求 85%）。
const double kResultBannerOpacity = 0.85;

/// 结果页（SPEC 3.3 + 用户需求 1/3/7 + 用户反馈 M16 第 3 条）：
/// **一次识别的全部题目在同一页纵向显示完成**，不再会话内分页；
/// 顶栏底部「上一次识别 / 下一次识别」在多次识别（会话）之间切换，
/// 标题显示「第 N/M 次识别」；右上角可「重新生成」。
///
/// 用户反馈 M16 第 3 条：**停在结果页时电脑开始识别，页面上要能看见**——
/// 页顶浮起一条「电脑正在识别中…（N 张图片）」，出结果时变成「识别完成」，
/// 随后由「当前任务」页把新结果页推上来（见 `showsHostProgress` 的注释）。
///
/// 主机完成识别后由 LiveUpdates invalidate provider，
/// 本页 watch 着它们，因此会自动刷新出答案（不需要手动下拉）。
class ResultPage extends ConsumerStatefulWidget {
  final String sessionId;

  /// 非空时只在同合集内翻页（从合集列表进来看记录时用）。
  final String? collectionId;

  const ResultPage({
    super.key,
    required this.sessionId,
    this.collectionId,
  });

  @override
  ConsumerState<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends ConsumerState<ResultPage> {
  late String _currentId = widget.sessionId;
  bool _reanalyzing = false;

  void _switchTo(String sessionId) {
    setState(() => _currentId = sessionId);
  }

  /// 字号快捷调节（SPEC 4.1：字号可调）。
  void _bumpFont(double delta) {
    final s = ref.read(androidAppProvider).settings;
    s.updateApp(
        s.app.copyWith(fontSize: (s.app.fontSize + delta).clamp(12, 32)));
    ref.read(settingsRevisionProvider.notifier).state++;
  }

  /// 「重新生成」（用户需求 7）：让主机按既有页序重跑。
  Future<void> _reanalyze() async {
    final pairing = ref.read(pairingProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (pairing == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('还没有配对，无法重新生成')));
      return;
    }
    setState(() => _reanalyzing = true);
    try {
      final gateway = ref.read(hostGatewayFactoryProvider)(pairing);
      final result = await gateway.reanalyze(_currentId);
      ref.read(activeTaskProvider.notifier).begin(
            taskId: result.taskId,
            sessionId: _currentId,
            imageCount:
                ref.read(sessionImagesProvider(_currentId)).valueOrNull?.length ??
                    1,
          );
      messenger?.showSnackBar(const SnackBar(
          content: Text('已请求电脑重新生成，完成后本页会自动刷新')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
          content: Text(isNoActiveCollection(e)
              ? '请先在电脑上选择任务合集'
              : '重新生成失败：${hostErrorMessage(e)}')));
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = ref.watch(androidAppProvider);
    final fontSize = app.settings.app.fontSize;

    final listAsync = ref.watch(sessionsProvider(widget.collectionId));
    final currentAsync = ref.watch(sessionProvider(_currentId));
    final questionsAsync = ref.watch(sessionQuestionsProvider(_currentId));
    final imagesAsync = ref.watch(sessionImagesProvider(_currentId));

    final sessions = <Session>[...?listAsync.valueOrNull];
    final current = currentAsync.valueOrNull;
    var index = sessions.indexWhere((s) => s.sessionId == _currentId);
    if (index < 0) {
      if (current != null) {
        sessions.insert(0, current);
        index = 0;
      } else {
        index = 0;
      }
    }
    final missing = currentAsync.hasValue && current == null;
    final questions = questionsAsync.valueOrNull ?? const <Question>[];
    final imageCount = imagesAsync.valueOrNull?.length ?? 1;
    final dark = theme.brightness == Brightness.dark;
    final style = current == null
        ? null
        : statusStyle(current.status.wire, dark: dark);

    final loading = !listAsync.hasValue && listAsync.isLoading ||
        (!missing && !questionsAsync.hasValue && questionsAsync.isLoading);

    final hasPrev = index < sessions.length - 1; // 上一次 = 更早
    final hasNext = index > 0; // 下一次 = 更新

    // 电脑正在识别 / 刚识别完（用户反馈 M16 第 3 条；M18 第 3 条调层级与透明度）。
    final task = ref.watch(activeTaskProvider);
    final pages = task.imageCount < 1 ? 1 : task.imageCount;
    final Widget? hostBanner = showsHostProgress(task, _currentId)
        ? NextRoundBanner(
            key: const ValueKey('result-next-banner'),
            textKey: const ValueKey('result-next-banner-text'),
            text: '电脑正在识别中…（$pages 张图片）',
            spinning: true,
            opacity: kResultBannerOpacity,
          )
        : showsHostDone(task, _currentId)
            ? NextRoundBanner(
                key: const ValueKey('result-next-banner'),
                textKey: const ValueKey('result-next-banner-text'),
                text: '识别完成，正在打开新结果…',
                spinning: false,
                opacity: kResultBannerOpacity,
              )
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('识别结果',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (sessions.isNotEmpty && current != null) ...[
              const SizedBox(height: 2),
              Text(
                // 用户需求 1：标题仍是「第 N/M 次识别」。
                '第 ${index + 1} / ${sessions.length} 次识别 · '
                '${timeLabel(current)}',
                key: const ValueKey('result-position'),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          if (_reanalyzing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              key: const ValueKey('reanalyze'),
              tooltip: '重新生成',
              icon: const Icon(Icons.autorenew),
              onPressed: missing ? null : _reanalyze,
            ),
          IconButton(
            tooltip: '缩小字号',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.text_decrease),
            onPressed: fontSize <= 12 ? null : () => _bumpFont(-1),
          ),
          IconButton(
            tooltip: '放大字号',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.text_increase),
            onPressed: fontSize >= 32 ? null : () => _bumpFont(1),
          ),
          const SizedBox(width: 4),
        ],
        bottom: sessions.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('prev-session'),
                        onPressed: hasPrev
                            ? () => _switchTo(sessions[index + 1].sessionId)
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('上一次识别'),
                      ),
                      const Spacer(),
                      Text('${index + 1} / ${sessions.length}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      TextButton.icon(
                        key: const ValueKey('next-session'),
                        onPressed: hasNext
                            ? () => _switchTo(sessions[index - 1].sessionId)
                            : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const Text('下一次识别'),
                        iconAlignment: IconAlignment.end,
                      ),
                    ],
                  ),
                ),
              ),
      ),
      // 内容 + 浮在它**上面**的「电脑正在识别中」悬浮窗（用户反馈 M16 第 3 条）。
      //
      // M18 第 3 条：用户原话「安卓端已经进入识别结果页面后，windows 端识别时
      // 安卓端的悬浮窗提示渲染在识别结果题目下。修改为渲染到最上层」。Stack 里
      // **后画的在上面** [原实现把浮层放在第一个孩子，于是被题目盖住] —— 所以
      // 浮层必须是最后一个孩子，下面 `Positioned` 的内容才能被它压住。
      // 透明度由 `kResultBannerOpacity` 给到卡片底色（文字仍完全不透明）。
      body: Stack(
        children: [
          Positioned.fill(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : missing
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: '本次识别已不存在',
                        message: '可能已被清理或删除。返回列表挑选其它记录即可。',
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('返回列表'),
                          ),
                        ],
                      )
                    : questions.isEmpty
                        ? _emptyResult(context, current, style)
                        : RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(sessionsProvider);
                              ref.invalidate(sessionQuestionsProvider);
                              ref.invalidate(sessionImagesProvider);
                              await ref
                                  .read(sessionQuestionsProvider(_currentId).future);
                            },
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(top: 6, bottom: 16),
                              children: [
                                if (current != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (style != null)
                                          StatusPill(
                                            icon: style.icon,
                                            label: style.label,
                                            color: style.color,
                                          ),
                                        StatusPill(
                                          label: '共 ${questions.length} 题',
                                          color: theme.colorScheme.onSurfaceVariant,
                                          filled: false,
                                        ),
                                        StatusPill(
                                          key: const ValueKey('result-image-count'),
                                          icon: Icons.image_outlined,
                                          label: '$imageCount 张图片',
                                          color: theme.colorScheme.onSurfaceVariant,
                                          filled: false,
                                        ),
                                        if (current.collectionId != null)
                                          StatusPill(
                                            label: '合集记录',
                                            color: theme.colorScheme.onSurfaceVariant,
                                            filled: false,
                                          ),
                                        if (current.aiModel != null &&
                                            current.aiModel!.isNotEmpty)
                                          StatusPill(
                                            label: current.aiModel!,
                                            color: theme.colorScheme.onSurfaceVariant,
                                            filled: false,
                                          ),
                                      ],
                                    ),
                                  ),
                                // 一次识别的所有题目在同一页纵向显示（用户需求 1）。
                                for (final q in questions)
                                  QuestionCard(question: q, fontSize: fontSize),
                              ],
                            ),
                          ),
          ),
          // 最后画的在最上层（M18 第 3 条）：一定要留在 `Stack` 的孩子末尾。
          if (hostBanner != null)
            Positioned(left: 12, right: 12, top: 8, child: hostBanner),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(padding: EdgeInsets.all(8), child: Disclaimer()),
      ),
    );
  }

  Widget _emptyResult(BuildContext context, Session? session, dynamic style) {
    final failed = session?.status == TaskState.failed;
    return EmptyState(
      icon: failed ? Icons.error_outline : Icons.inbox_outlined,
      title: failed ? '分析失败' : '本次识别没有题目',
      message: failed
          ? (session?.errorMessage ?? session?.errorCode ?? '原因未知，可在电脑端重试')
          : '截图里可能没有可识别的题目，换个更清晰的截图再试。',
      actions: [
        OutlinedButton.icon(
          key: const ValueKey('reload-result'),
          onPressed: () {
            ref.invalidate(sessionQuestionsProvider);
            ref.invalidate(sessionProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重新加载'),
        ),
        FilledButton.icon(
          onPressed: _reanalyze,
          icon: const Icon(Icons.autorenew, size: 18),
          label: const Text('重新生成'),
        ),
        if (style != null)
          StatusPill(
            icon: style.icon,
            label: style.label,
            color: style.color,
          ),
      ],
    );
  }
}

/// image_picker 的薄封装。
Future<Uint8List?> pickImageFromGallery() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 100, // 压缩统一走 ImageProc
  );
  if (picked == null) return null;
  return Uint8List.fromList(await picked.readAsBytes());
}

class DecodedImageX {
  final int width;
  final int height;
  final Uint8List bgra;
  DecodedImageX(this.width, this.height, this.bgra);
}

DecodedImageX? decodeImageBytes(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final bgra = decoded.getBytes(order: img.ChannelOrder.bgra);
    return DecodedImageX(
        decoded.width, decoded.height, Uint8List.fromList(bgra));
  } catch (_) {
    return null;
  }
}
