import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:quizsync_core/quizsync_core.dart';
import 'package:window_manager/window_manager.dart';

import '../services/clipboard_watcher.dart';
import '../services/hotkeys.dart';
import '../services/screen_capture.dart';
import 'analysis_workflow.dart';
import 'app_scope.dart';

/// 采集协调器：热键 / 剪贴板 / 托盘 / 拖入粘贴 → 截图处理 → 工作流。
/// 平台相关（win32 / 托盘）；逻辑上只做「取字节 → 交给 workflow」。
class CaptureCoordinator {
  final WidgetRef Function() refOf;
  final BuildContext Function() contextOf;
  final ScreenCaptureService capture;
  final String imageDir;

  ClipboardWatcher? _clipboardWatcher;
  bool _busyFlag = false;

  /// 本次提交了几张图（M32：悬浮窗上那条「识别进行中…」要写明张数）。
  int _submittingImages = 0;

  /// 是否正在识别（用户反馈 11：悬浮球据此显示「识别中」状态图）。
  bool get busy => _busyFlag;

  /// 悬浮窗「识别进行中」浮层的文案（用户需求 1.10）。
  String get busyLabel => _submittingImages > 1
      ? '识别进行中…（本次 $_submittingImages 张图片）'
      : '识别进行中…';

  /// 「正在识别」状态变化回调（悬浮球换状态图用）。
  final List<void Function()> busyListeners = [];

  set _busy(bool value) {
    if (_busyFlag == value) return;
    _busyFlag = value;
    // 结束识别时把「本次几张图」一起清掉，悬浮窗的浮层文案才不会是上一轮的。
    if (!value) _submittingImages = 0;
    for (final l in busyListeners) {
      try {
        l();
      } catch (_) {
        // 单个监听失败不影响主流程。
      }
    }
  }

  bool get _busy => _busyFlag;

  /// 多页暂存区（用户需求 4）：按下「追加页」热键把每一页放进这里等待上传，
  /// 到达上限或按下「截止」热键时一起送出。UI 据此显示「已暂存 N 页」。
  final List<WorkflowPage> _staged = [];

  /// 暂存页数变化回调（UI 显示进度条/提示）。
  void Function()? onStagingChanged;

  /// 额外的暂存变化监听（外壳用它刷新托盘提示；可以有多个，互不覆盖）。
  final List<void Function()> stagingListeners = [];

  /// 本次多页会话结束时的回调（结果 toast 之外的处理，如跳转会话）。
  void Function(String sessionId)? onSessionReady;

  CaptureCoordinator({
    required this.refOf,
    required this.contextOf,
    ScreenCaptureService? capture,
    required this.imageDir,
  }) : capture = capture ?? ScreenCaptureService();

  List<WorkflowPage> get stagedPages => List.unmodifiable(_staged);
  int get stagedCount => _staged.length;
  bool get hasStaged => _staged.isNotEmpty;

  /// 「截屏识别」热键 / 托盘「截取屏幕」/ 悬浮窗「识别一张」的入口。
  ///
  /// M46 第 1 条（用户要求「截屏逻辑和 server 类似」）：
  /// - **不在多页模式**（暂存区空）→ 截一张屏立刻识别；
  /// - **已经在多页模式**（攒着页）→ **结束多页**：把已攒的图一起上传识别，
  ///   **不再多截一张**（按 F8 的语义就是「我不再补页了，开始识别」）。
  ///
  /// 用户反馈 12：识别全程**后台静默**——不再主动把窗口弹到前台；
  /// 窗口本来就开着的话，SnackBar 照样能在窗口里看到。
  Future<void> captureAndAnalyze() async {
    if (_busy) {
      _toast('正在分析上一张，请稍候', reveal: true);
      return;
    }
    // M47：闸门必须**同步**置位。下面两个 guard 都是真 await（读安全存储 / 读库），
    // 而 `_busy = true` 原来排在它们之后 —— 连按两次 F8 时两次都能通过 `if (_busy)`，
    // 于是真的调用两次 AI（花两次钱、出两条记录）。
    _busy = true;
    try {
      if (intentOfCaptureHotkey(_staged.length) ==
          CaptureIntent.finishMultipage) {
        _toast('结束多页模式：上传本次 ${_staged.length} 张图片识别');
        // 闸门已经在自己手里：走内部实现，不要再过一遍 submitStaged 的闸门。
        await _submitStagedGuarded();
        return;
      }
      // M33 第 14 条：**先让用户把 API Key 填好并保存**，再弹首次识别的隐私告知
      // （原来的顺序是「先弹隐私告知、填 Key 是后面的事」，用户明确要求调过来）。
      if (!await _guardApiKey()) return;
      if (!await _guardCollection()) return;
      final shot = await _runCapture();
      if (shot == null) return;
      if (ImageProc.isAllBlack(shot.bgra, shot.width, shot.height)) {
        _toast('截屏内容为空白/黑图（该应用可能禁止截屏）');
        return;
      }
      final processed = ImageProc.toJpeg(shot.bgra, shot.width, shot.height);
      await _submit(
        jpeg: processed.jpeg,
        width: processed.width,
        height: processed.height,
        hash: sha256Hex(processed.jpeg),
        source: '屏幕截图',
      );
    } catch (e) {
      _toast('截屏失败：$e');
    } finally {
      _busy = false;
    }
  }

  // ============================================================
  // 多页识别（用户需求 4；M46 第 1 条合并成**一个**热键）
  // ============================================================

  /// 「多页模式」热键 / 托盘 / 悬浮窗「多页识别」「继续添加页」。
  ///
  /// - 第一下：进入多页模式并抓第 1 张；
  /// - 之后每按一下追加一页；
  /// - 抓满上限（默认 6 张）时，[autoUploadAtLimit] 为 true 就直接上传识别
  ///   —— 用户要求「累积到第六张则截取完第六张自动上传识别」。
  ///
  /// [autoUploadAtLimit] 只有悬浮窗上的「继续添加页」按钮传 false：那是用户明确
  /// 点的一次「再加一页」，到上限时应该提示他点「结束并上传」，而不是替他上传。
  Future<void> multipageCapture({bool autoUploadAtLimit = true}) async {
    if (_busy) {
      _toast('正在识别上一组，请稍候再追加', reveal: true);
      return;
    }
    // M47：原来这条入口**从不置 `_busy`**（既拦不住并发追加，也拦不住「正在
    // 识别时又抓一页」）。闸门同样是先置位再做 await。
    _busy = true;
    try {
      if (!await _guardApiKey()) return;
      if (!await _guardCollection()) return;
      final limit = _multiPageLimit();
      final intent =
          intentOfMultipageHotkey(staged: _staged.length, limit: limit);
      if (intent == CaptureIntent.multipageFull) {
        if (autoUploadAtLimit) {
          _toast('已达上限 $limit 页，正在上传本次全部页面');
          await _submitStagedGuarded();
        } else {
          _toast('已达上限 $limit 页，请点「结束多页识别」上传');
        }
        return;
      }
      final page = await _capturePage();
      if (page == null) return;
      _staged.add(page);
      _notifyStaging();
      if (shouldAutoUploadAfterCapture(staged: _staged.length, limit: limit)) {
        if (autoUploadAtLimit) {
          _toast('已抓满 $limit 张，自动开始识别');
          await _submitStagedGuarded();
        } else {
          _toast('已暂存 $limit/$limit 张（已到上限，点「结束多页识别」上传）');
        }
        return;
      }
      _toast('已暂存第 ${_staged.length}/$limit 页'
          '（继续按可加页，按「截屏识别」键结束多页并上传本次全部页面）');
    } finally {
      _busy = false;
    }
  }

  /// 上传暂存区里的全部页面作为**一次识别**（自己过闸门与 `_busy`）。
  Future<void> submitStaged() async {
    if (_staged.isEmpty) {
      _toast('暂存区是空的：先按「多页模式」热键截图');
      return;
    }
    if (_busy) {
      // M47：原来这里先把暂存区清空再报「本次 N 页已丢弃」——识别忙的时候
      // 用户抓的页就白抓了。现在保留暂存，忙完再按一次即可。
      _toast('正在识别上一组，请稍候再上传', reveal: true);
      return;
    }
    _busy = true;
    try {
      await _submitStagedGuarded();
    } finally {
      _busy = false;
    }
  }

  /// 已经持有 `_busy` 时的暂存区上传：闸门 + 提交都在这里。
  Future<void> _submitStagedGuarded() async {
    if (_staged.isEmpty) {
      _toast('暂存区是空的：先按「多页模式」热键截图');
      return;
    }
    // M47：这里原来两个前置检查都不做（其余四个识别入口都做）——用户把当前
    // 合集删掉之后按「结束多页」/悬浮窗「结束并上传」照样会调 AI 并落成
    // 「未分类」。检查放在**清空暂存区之前**：合集没选好时已抓的页面留着，
    // 选完合集再按一次即可（原来会先把暂存清掉再报错）。
    if (!await _guardApiKey()) return;
    if (!await _guardCollection()) return;
    final pages = List<WorkflowPage>.from(_staged);
    _staged.clear();
    _notifyStaging();
    try {
      await _submitPages(pages, source: '多页截图');
    } catch (e) {
      _toast('分析失败：$e', reveal: true);
    }
  }

  /// 清空暂存区（用户取消本次多页）。
  void clearStaging() {
    if (_staged.isEmpty) return;
    _staged.clear();
    _notifyStaging();
    _toast('已清空多页暂存区');
  }

  /// 重新识别**已经识别过的某一次**（M32 用户需求 1.4：悬浮窗上的「重新识别」）。
  ///
  /// 与主界面「重新分析」是同一条链路（`AnalysisWorkflow.retrySession`，
  /// `force: true` 强制真的再问一次 AI，不走缓存）；多页会话会从本机图片目录
  /// 取回每一页，缺页时把原因如实告诉用户。
  Future<void> regenerate(String sessionId) async {
    if (_busy) {
      _toast('正在识别上一组，请稍候', reveal: true);
      return;
    }
    // M47：这条入口置位之前有 3 个 await（读会话 / 读 Key / 读原图），悬浮窗上
    // 连点两下「重新识别」会真的跑两次 —— 闸门一律同步置位。
    final ref = refOf();
    _busy = true;
    try {
      final repo = ref.read(repoProvider);
      final session = await repo.getSession(sessionId, includeDeleted: true);
      if (session == null) {
        _toast('这条识别记录已经不在了');
        return;
      }
      final apiKey = await ref.read(apiKeyReaderProvider)();
      if ((apiKey ?? '').isEmpty) {
        _toast('尚未配置 AI：请到设置页填写 API Key 与模型', reveal: true);
        return;
      }
      final jpeg = await loadSessionFirstImage(repo, session);
      if (jpeg == null) {
        _toast('原始截图文件不存在，无法重新识别（可在设置里开启「保存图片」）',
            reveal: true);
        return;
      }
      final workflow = ref.read(workflowProvider);
      workflow.readImageFile = imageFileReader(imageDir);
      final pages = await repo.imageHashesOf(sessionId);
      _submittingImages = pages.isEmpty ? 1 : pages.length;
      final settings = ref.read(settingsProvider);
      final result = await workflow.retrySession(
        sessionId: sessionId,
        jpeg: jpeg,
        config: AiConfig(
          providerId: settings.ai.providerId,
          baseUrl: settings.ai.baseUrl,
          apiKey: apiKey ?? '',
          model: settings.ai.model,
          timeoutSeconds: settings.ai.timeoutSeconds,
        ),
      );
      _toast(
        result.message ??
            (result.ok ? '已重新识别' : (result.errorMessage ?? '重新识别失败')),
        reveal: !result.ok,
      );
      if (result.ok && result.sessionId.isNotEmpty) {
        onSessionReady?.call(result.sessionId);
      }
    } on StateError catch (e) {
      _toast(e.message, reveal: true);
    } catch (e) {
      _toast('重新识别失败：$e', reveal: true);
    } finally {
      _busy = false;
      _submittingImages = 0;
    }
    ref.invalidate(usageTodayProvider);
  }

  void _notifyStaging() {
    onStagingChanged?.call();
    for (final l in stagingListeners) {
      try {
        l();
      } catch (_) {
        // 单个监听失败不影响其他监听与主流程。
      }
    }
  }

  int _multiPageLimit() {
    try {
      return refOf().read(settingsProvider).app.multiPageLimit;
    } catch (_) {
      return kDefaultMultiPageLimit;
    }
  }

  /// 截取一页（隐藏窗口 → 取帧 → 转 JPEG）。
  Future<WorkflowPage?> _capturePage() async {
    try {
      final shot = await _runCapture();
      if (shot == null) return null;
      if (ImageProc.isAllBlack(shot.bgra, shot.width, shot.height)) {
        _toast('截屏内容为空白/黑图（该应用可能禁止截屏）');
        return null;
      }
      final processed = ImageProc.toJpeg(shot.bgra, shot.width, shot.height);
      return WorkflowPage(
        jpeg: processed.jpeg,
        width: processed.width,
        height: processed.height,
        hash: sha256Hex(processed.jpeg),
      );
    } catch (e) {
      _toast('截屏失败：$e');
      return null;
    }
  }

  /// 剪贴板新图片回调。
  Future<void> onClipboardImage(CapturedImage image) async {
    if (_busy) {
      // 静默丢弃会让用户以为热键/剪贴板失效：明确提示。
      _toast('正在分析上一张，本次截图已忽略');
      return;
    }
    // M47：闸门同步置位（两个 guard 都是真 await，理由见 captureAndAnalyze）。
    _busy = true;
    try {
      if (!await _guardApiKey()) return;
      if (!await _guardCollection()) return;
      if (ImageProc.isAllBlack(image.bgra, image.width, image.height)) {
        return;
      }
      final processed =
          ImageProc.toJpeg(image.bgra, image.width, image.height);
      await _submit(
        jpeg: processed.jpeg,
        width: processed.width,
        height: processed.height,
        hash: sha256Hex(processed.jpeg),
        source: '剪贴板',
      );
    } catch (_) {
      // 静默：剪贴板路径不打扰用户。
    } finally {
      _busy = false;
    }
  }

  /// 托盘菜单「从剪贴板读取」：手动取一次当前剪贴板图片并分析。
  /// （剪贴板监听只管「新」图片，已在剪贴板里的内容不会触发。）
  Future<void> analyzeClipboardNow() async {
    CapturedImage? image;
    try {
      image = readClipboardImageNow();
    } catch (e) {
      _toast('读取剪贴板失败：$e', reveal: true);
      return;
    }
    if (image == null) {
      _toast('剪贴板里没有图片（可先截图或复制一张图）', reveal: true);
      return;
    }
    await onClipboardImage(image);
  }

  /// 主窗口粘贴（Ctrl+V）/ 拖入的图片字节。
  Future<void> analyzeBytes(Uint8List bytes, {String source = '图片文件'}) async {
    if (_busy) {
      _toast('正在分析上一张，请稍候', reveal: true);
      return;
    }
    // M47：闸门同步置位（理由见 captureAndAnalyze）。
    _busy = true;
    try {
      if (!await _guardApiKey()) return;
      if (!await _guardCollection()) return;
      // 已是 JPEG（常见情形）：直接按规则再压一遍统一规格。
      final decoded = decodeImage(bytes);
      if (decoded == null) {
        _toast('无法识别的图片格式');
        return;
      }
      final processed =
          ImageProc.toJpeg(decoded.bgra, decoded.width, decoded.height);
      await _submit(
        jpeg: processed.jpeg,
        width: processed.width,
        height: processed.height,
        hash: sha256Hex(processed.jpeg),
        source: source,
      );
    } catch (e) {
      _toast('分析失败：$e');
    } finally {
      _busy = false;
    }
  }

  Future<CapturedScreen?> _runCapture() async {
    // 截屏前隐藏主窗口（SPEC 2.1：不能把 UI 拍进图里）。
    return capture.hideWindowWhile(() => capture.captureCursorMonitor());
  }

  /// 单页入口：建会话 + 分析。
  Future<void> _submit({
    required Uint8List jpeg,
    required int width,
    required int height,
    required String hash,
    required String source,
  }) async {
    final ref = refOf();
    final settings = ref.read(settingsProvider);
    final apiKey = await ref.read(apiKeyReaderProvider)();
    if ((apiKey ?? '').isEmpty) {
      _toast('尚未配置 AI：请到设置页填写 API Key 与模型', reveal: true);
      return;
    }
    final dir = imageDir;
    final saveFiles = settings.app.saveImageFiles;

    final workflow = ref.read(workflowProvider);
    _submittingImages = 1;
    workflow.saveImageFile = saveFiles
        ? (h, bytes) async {
            final file = File('$dir/$h.jpg');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes);
            await ref.read(repoProvider).setImageLocalPath(h, file.path);
          }
        : null;
    workflow.readImageFile =
        saveFiles ? (h) async => File('$dir/$h.jpg').existsSync() ? await File('$dir/$h.jpg').readAsBytes() : null : null;
    final result = await workflow.run(
      jpeg: jpeg,
      imageHash: hash,
      width: width,
      height: height,
      config: AiConfig(
        providerId: settings.ai.providerId,
        baseUrl: settings.ai.baseUrl,
        apiKey: apiKey ?? '',
        model: settings.ai.model,
        timeoutSeconds: settings.ai.timeoutSeconds,
      ),
    );
    _toast(
        result.message ??
            (result.ok ? '$source：已出结果' : (result.errorMessage ?? '分析失败')),
        // M30（用户实测踩到）：本机识别保持静默，但**失败必须让用户看见** —— 热键明明
        // 生效了，却因为「截到的是聊天窗口 → no_question_found → SnackBar 只画在应用
        // 窗口里、而窗口在其他窗口后面」而看起来像「热键没反应」。
        reveal: !result.ok);
    if (result.ok && result.sessionId.isNotEmpty) {
      onSessionReady?.call(result.sessionId);
    }
    await _pruneCache(settings.app.imageCacheLimit);
    // 用量数字刷新（设置页的「今日用量」）。
    ref.invalidate(usageTodayProvider);
  }

  /// 多页入口（用户需求 4）：N 页作为一次识别。
  Future<void> _submitPages(List<WorkflowPage> pages,
      {required String source}) async {
    final ref = refOf();
    final settings = ref.read(settingsProvider);
    final apiKey = await ref.read(apiKeyReaderProvider)();
    if ((apiKey ?? '').isEmpty) {
      _toast('尚未配置 AI：请到设置页填写 API Key 与模型', reveal: true);
      return;
    }
    final dir = imageDir;
    final saveFiles = settings.app.saveImageFiles;
    final workflow = ref.read(workflowProvider);
    _submittingImages = pages.length;
    workflow.saveImageFile = saveFiles
        ? (h, bytes) async {
            final file = File('$dir/$h.jpg');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes);
            await ref.read(repoProvider).setImageLocalPath(h, file.path);
          }
        : null;
    workflow.readImageFile = saveFiles
        ? (h) async {
            final file = File('$dir/$h.jpg');
            if (!await file.exists()) return null;
            return file.readAsBytes();
          }
        : null;

    final result = await workflow.runMulti(
      pages: pages,
      config: AiConfig(
        providerId: settings.ai.providerId,
        baseUrl: settings.ai.baseUrl,
        apiKey: apiKey ?? '',
        model: settings.ai.model,
        timeoutSeconds: settings.ai.timeoutSeconds,
      ),
    );
    _toast(
        result.message ??
            (result.ok
                ? '$source：${pages.length} 页已出结果'
                : (result.errorMessage ?? '分析失败')),
        // 同单页路径：失败要把窗口带回来，否则热键生效了也像没反应。
        reveal: !result.ok);
    if (result.ok && result.sessionId.isNotEmpty) {
      onSessionReady?.call(result.sessionId);
    }
    await _pruneCache(settings.app.imageCacheLimit);
    ref.invalidate(usageTodayProvider);
  }

  /// 本地图片缓存上限（用户需求 5）：0 = 不设限。
  Future<void> _pruneCache(int limit) async {
    try {
      final dir = imageDir;
      await pruneImageFiles(
        refOf().read(repoProvider),
        (hash) => '$dir/$hash.jpg',
        maxFiles: limit,
        onDelete: (path) async {
          final file = File(path);
          if (await file.exists()) await file.delete();
        },
      );
    } catch (_) {
      // 清理失败不影响结果展示。
    }
  }

  /// 用户需求 8/12：没有选中合集就不允许开始任务（任务必须落在合集里）。
  Future<bool> _guardCollection() async {
    final ref = refOf();
    try {
      final id = await ref.read(repoProvider).getSetting(kActiveCollectionKey);
      if (id != null && id.isNotEmpty) {
        final c = await ref.read(repoProvider).getCollection(id);
        if (c != null) return true;
      }
    } catch (_) {
      // 读库失败按未选择处理。
    }
    _toast('请先新建或选择一个任务合集（左侧「切换合集」）', reveal: true);
    return false;
  }

  /// 没有 API Key 就别往下走 —— 先让用户去「API 配置」填好并保存。
  ///
  /// M34 第 1 条：隐私告知已经挪到「首次保存 API Key」那一步（见
  /// `ui/settings/api_settings_page.dart`），识别流程里**不再**弹任何告知窗 ——
  /// 那时用户往往在别的应用里，弹窗既打断又容易被忽略。
  Future<bool> _guardApiKey() async {
    try {
      final key = await refOf().read(apiKeyReaderProvider)();
      if ((key ?? '').trim().isNotEmpty) return true;
    } catch (_) {
      // 读 Key 失败按「没配」处理（安全侧）。
    }
    _toast('尚未配置 AI：请先到「设置 → API 配置」填写 API Key 并保存', reveal: true);
    return false;
  }

  /// 窗口隐藏到托盘时，结果 / 提示都发生在不可见的窗口里，
  /// 用户观感就是「热键没反应」——所有可见反馈前先把窗口带回来。
  Future<void> _reveal() async {
    try {
      if (!await windowManager.isVisible()) {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (_) {}
  }

  void _toast(String message, {bool reveal = false}) {
    // 只有「用户必须知道」的失败/前置条件才把窗口带回来（[reveal]）；
    // 正常识别流程保持后台静默（用户反馈 12）。
    if (reveal) _reveal();
    final context = contextOf();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  /// 按设置启停剪贴板监听。
  void syncClipboardWatcher(bool enabled) {
    if (enabled) {
      _clipboardWatcher ??= ClipboardWatcher(onImage: onClipboardImage)
        ..start();
    } else {
      _clipboardWatcher?.stop();
      _clipboardWatcher = null;
    }
  }

  void dispose() {
    _clipboardWatcher?.stop();
  }
}

/// 读取某次识别的**首页原图**（库里记录的 `local_path`）；读不到返回 null。
///
/// M32：主界面「重新分析」与悬浮窗「重新识别」共用同一份取图逻辑。
Future<Uint8List?> loadSessionFirstImage(
    CoreRepository repo, Session session) async {
  final meta = await repo.getImage(session.imageHash);
  final path = meta?.localPath;
  if (path == null) return null;
  try {
    return Uint8List.fromList(await File(path).readAsBytes());
  } catch (_) {
    return null;
  }
}

/// 按图片哈希从本机图片目录读回原图（多页会话重新识别时取第 2..N 页）。
Future<Uint8List?> Function(String) imageFileReader(String imageDir) =>
    (hash) async {
      final file = File('$imageDir/$hash.jpg');
      if (!await file.exists()) return null;
      return file.readAsBytes();
    };

/// 解码任意图片字节到 BGRA（拖入文件 / 粘贴非 DIB 情形）。
class DecodedImage {
  final int width;
  final int height;
  final Uint8List bgra;
  DecodedImage(this.width, this.height, this.bgra);
}

DecodedImage? decodeImage(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final bgra = decoded.getBytes(order: img.ChannelOrder.bgra);
    return DecodedImage(decoded.width, decoded.height, Uint8List.fromList(bgra));
  } catch (_) {
    return null;
  }
}
