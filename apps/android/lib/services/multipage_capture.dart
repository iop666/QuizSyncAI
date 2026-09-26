import 'dart:typed_data';

import 'package:quizsync_core/quizsync_core.dart';

import 'android_capture_controller.dart' show CaptureResult;

/// 一次多页手势的处理结果。
enum MultiPageEvent {
  /// 又加了一页（继续长按可加更多，短按结束）。
  pageAdded,

  /// 截屏失败（黑图 / 会话失效）。
  captureFailed,

  /// 上传失败：多页模式已取消，不要留下半截任务。
  uploadFailed,

  /// 已提交多页任务（到上限自动提交，或用户短按结束）。
  submitted,
}

/// 多页识别手势状态机（用户需求 4/11）。
///
/// 分工：Kotlin 悬浮球只上报「短按 / 长按」两种手势；
/// **是否处于多页模式由 Dart 判断**（本类），业务逻辑因此可以在本机单测。
///
/// 语义（M49 与 Windows 端手势对齐）：
/// - 长按（未在多页模式）：开始多页，截一页并**立即上传**，记住 hash；
/// - 长按（已在多页模式）：再加一页，直到 [limitOf] 上限；
/// - 到上限：提示 + **自动**用已收集的页创建多页任务（并退出多页模式）；
/// - 短按（已在多页模式）：**只提交已收集的页**，不再补截一页。
class MultiPageCapture {
  MultiPageCapture({
    required this.limitOf,
    required this.capturePage,
    required this.uploadPage,
    required this.submitPages,
    this.onMessage,
    this.onStateChanged,
  });

  /// 页数上限来源（读 `AppSettings.multiPageLimit`，默认 6）。
  final int Function() limitOf;

  /// 截取一页（JPEG 字节；null = 失败）。
  final Future<Uint8List?> Function() capturePage;

  /// 立即上传一页，返回主机侧 hash；null = 失败。
  final Future<String?> Function(Uint8List jpeg) uploadPage;

  /// 用收集到的页创建多页任务并等待结果。
  final Future<CaptureResult> Function(List<String> hashes) submitPages;

  /// 用户可见的过程提示（悬浮球在其他应用上时宿主会转成系统 Toast）。
  final void Function(String message)? onMessage;

  /// 多页模式开关变化（用于把状态推给 Kotlin 悬浮球换色）。
  final void Function(bool active, int pages)? onStateChanged;

  final List<String> _hashes = [];

  bool get active => _hashes.isNotEmpty;

  int get pageCount => _hashes.length;

  List<String> get hashes => List<String>.unmodifiable(_hashes);

  void reset() {
    _hashes.clear();
    onStateChanged?.call(false, 0);
  }

  /// 长按：加一页；已到上限则提示并自动提交。
  Future<({MultiPageEvent event, CaptureResult? result})> longPress() async {
    final limit = limitOf().clamp(1, kHardMaxPagesPerTask);
    if (active && _hashes.length >= limit) {
      onMessage?.call('已达 $limit 页上限，正在提交识别…');
      return _submit();
    }

    final jpeg = await capturePage();
    if (jpeg == null) {
      onMessage?.call('截屏失败（该应用可能禁止截屏），多页识别已取消');
      reset();
      return (event: MultiPageEvent.captureFailed, result: null);
    }
    final hash = await uploadPage(jpeg);
    if (hash == null || hash.isEmpty) {
      onMessage?.call('上传失败，多页识别已取消');
      reset();
      return (event: MultiPageEvent.uploadFailed, result: null);
    }
    _hashes.add(hash);
    onStateChanged?.call(true, _hashes.length);
    if (_hashes.length >= limit) {
      // M47（SPEC 3.1：到达上限时提示「已达上限」并**自动**创建多页任务上传识别）：
      // 原来只在长按**开始时**判上限，于是抓满第 N 页之后还要用户再多长按一次
      // 才提交 —— 与契约和桌面端（热键抓满即自动上传）都不一致。
      onMessage?.call('已达 $limit 页上限，正在提交识别…');
      return _submit();
    }
    onMessage?.call(
        '已加入第 ${_hashes.length} 页（最多 $limit 页）：继续长按加页，短按结束并识别');
    return (event: MultiPageEvent.pageAdded, result: null);
  }

  /// 短按且已在多页模式：**只用已收集的页**创建多页任务。
  ///
  /// M49（用户反馈：手势看齐 Windows 端）：桌面端 F8「结束多页并上传已抓的图」
  /// 不会再多拍一张；安卓端原来把短按当成「最后一页 + 收尾」，用户想结束反而
  /// 被迫多截一张（多半是同一页、或已经翻过去不需要的内容），页数与预期不符。
  /// 现在短按 = 结束并识别，页数严格等于长按次数。
  Future<({MultiPageEvent event, CaptureResult? result})>
      tapToFinish() async {
    if (_hashes.isEmpty) {
      onMessage?.call('多页识别已取消：没有可用页面');
      reset();
      return (event: MultiPageEvent.captureFailed, result: null);
    }
    onMessage?.call('正在提交 ${_hashes.length} 页识别…');
    return _submit();
  }

  Future<({MultiPageEvent event, CaptureResult? result})> _submit() async {
    final hashes = List<String>.from(_hashes);
    reset();
    final result = await submitPages(hashes);
    return (event: MultiPageEvent.submitted, result: result);
  }
}
