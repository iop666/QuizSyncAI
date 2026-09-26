import '../quizsync_server_core.dart';
import 'capture.dart';
import 'constants.dart';
import 'server.dart';
import 'store.dart';
import 'tasks.dart';
import 'terminal.dart';

/// 两个热键动作背后的流程：**截图 → （可多页）→ AI → 推给手机**。
///
/// 运行模式（用户 1.0.0 优化第 5 条定稿，只有两个动作）：
///   - **截屏识别**（默认 F8，备用 Alt+Shift+Q）：不在多页模式 → 截一张立刻识别；
///     已在多页模式 → **结束多页**，把已抓的图一起上传识别；
///   - **多页模式**（默认 F9，备用 Alt+Shift+W）：第一次按进入多页并抓第 1 张，
///     继续按追加；攒满 6 张**自动上传识别**。
///
/// 备用键与主键**同时注册**（不是失败才回退）：本机有些键会被别的程序的键盘钩子
/// 吃掉，注册成功却永远收不到 WM_HOTKEY，两条一起才保险。
///
/// Server 是无人值守的后台服务，所以多页暂存只在内存里，且一次只跑一条链路：
/// 识别中再按热键只写一行日志、不排队（排队会让用户以为按键没生效，
/// 也可能白花 AI 配额）。
class CaptureFlow {
  final ScreenCapture capture;
  final ServerTasks tasks;
  final ServerStore store;
  final QuizSyncServer server;
  final Terminal log;

  /// 截屏实现（单测注入假的，不去碰真实屏幕）。
  final CapturedScreen Function() captureScreen;

  /// 多页暂存（多页键追加的页）。识别结束即清空。
  final List<PageInput> _pending = [];

  CaptureFlow({
    required this.capture,
    required this.tasks,
    required this.store,
    required this.server,
    required this.log,
    CapturedScreen Function()? captureScreen,
  }) : captureScreen =
            captureScreen ?? (() => capture.captureCursorMonitor());

  int get pendingPages => _pending.length;

  /// 是否已经在多页模式里（攒了至少一张）。
  bool get inMultipage => _pending.isNotEmpty;

  /// **截屏识别热键**（默认 F8，备用 Alt+Shift+Q）：
  /// 不在多页模式 → 截一张立刻识别；
  /// 已在多页模式 → **结束多页**，把已抓的图一起上传识别（不再多截一张）。
  Future<void> onCapture() async {
    if (tasks.busy) {
      log.log('截图', '正在识别中，本次按键先忽略（等结果出来再按）');
      return;
    }
    if (_pending.isNotEmpty) {
      final pages = List<PageInput>.from(_pending);
      log.log('截图', '结束多页模式：上传已抓取的 ${pages.length} 张图片识别');
      await _analyze(pages);
      return;
    }
    final page = _capturePage();
    if (page == null) return;
    log.log('截图', '单张截屏识别');
    await _analyze([page]);
  }

  /// **多页模式热键**（默认 F9，备用 Alt+Shift+W）：
  /// 第一次按进入多页并抓第 1 张；继续按追加下一张；攒满 [kHardMaxPagesPerTask]
  /// 张时**自动上传识别**（不必再按识别键）。
  Future<void> onMultipage() async {
    if (tasks.busy) {
      log.log('截图', '正在识别中，本次按键先忽略（等结果出来再按）');
      return;
    }
    if (_pending.length >= kHardMaxPagesPerTask) {
      log.log('截图', '多页已满 $kHardMaxPagesPerTask 张，稍后会自动上传识别');
      return;
    }
    final page = _capturePage();
    if (page == null) return;
    _pending.add(page);
    final count = _pending.length;

    if (count >= kHardMaxPagesPerTask) {
      final pages = List<PageInput>.from(_pending);
      log.log('截图', '已抓满 $count 张，自动上传识别');
      await _analyze(pages);
      return;
    }
    log.log('截图',
        '多页模式 $count/$kHardMaxPagesPerTask 张（继续按多页键追加，按识别键立即上传）');
  }

  /// 截图 + 压缩成 JPEG（失败只写日志，不让服务挂掉）。
  PageInput? _capturePage() {
    final CapturedScreen screen;
    try {
      screen = captureScreen();
    } catch (e) {
      log.error('截图失败：$e');
      return null;
    }
    log.log('截图', '已截屏');
    try {
      final processed =
          ImageProc.toJpeg(screen.bgra, screen.width, screen.height);
      return PageInput(
        hash: sha256Hex(processed.jpeg),
        jpeg: processed.jpeg,
        width: processed.width,
        height: processed.height,
      );
    } catch (e) {
      log.error('截图处理失败：$e');
      return null;
    }
  }

  /// 跑识别（同图命中时直接复用上次结果，不再花一次 AI）。
  Future<void> _analyze(List<PageInput> pages) async {
    if (pages.isEmpty) return;
    final hashes = pages.map((p) => p.hash).toList();
    final reusable = tasks.findReusable(hashes);
    if (reusable != null) {
      server.pushExistingResult(reusable);
      log.log('AI', '这张图之前识别过，直接复用上次结果（不再调用 AI）');
      _pending.clear();
      return;
    }

    log.log('AI', '正在识别 ${pages.length} 张图片…');
    final outcome = await tasks.run(
      pages: pages,
      sourceDevice: store.deviceId,
    );
    _pending.clear();
    if (outcome.ok) {
      log.log('AI',
          '识别完成：${outcome.questionCount} 道题（${outcome.latencyMs} ms）');
    } else {
      log.error('识别失败（${outcome.errorCode}）：${outcome.errorMessage}');
    }
  }
}
