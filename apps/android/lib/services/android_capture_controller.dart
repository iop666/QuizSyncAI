import 'package:flutter/services.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../state/app_state.dart';
import 'capture_source.dart';
import 'host_gateway.dart';
import 'live_updates.dart' show isNoActiveCollection;
import 'multipage_capture.dart';

/// 一次截屏分析的最终结果（宿主据此更新「当前任务」页状态）。
class CaptureResult {
  final bool ok;
  final String? sessionId;
  final String message;

  const CaptureResult.ok(this.sessionId)
      : ok = true,
        message = '';
  const CaptureResult.failed(this.message)
      : ok = false,
        sessionId = null;
}

/// 采集控制器（M5 / 用户需求 3、4、11、12）：
/// 悬浮球手势 → 截屏 → 上传分析 → 后台静默收尾（发通知 + 更新当前任务页）。
///
/// 手势语义（Kotlin 只上报「短按 / 长按」，模式判断在 Dart）：
/// - 短按（非多页）：单图识别；
/// - 长按：进入并累加多页（每页立即上传），到上限自动提交；
/// - 短按（多页中）：只提交已截取的页并退出多页模式（M49 起不再补截一页）。
class AndroidCaptureController {
  final AndroidAppState app;
  final CaptureSource captureSource;
  final void Function(String sessionId) onResultReady;
  final void Function(String message) onMessage;

  /// 截屏字节落盘（离线补跑的前提）。未设置时离线失败只能丢弃。
  Future<void> Function(String hash, Uint8List bytes)? saveImageFile;

  /// 任务已提交给主机（宿主据此显示「N 张图片识别中…」）。
  ///
  /// 用户需求 3：识别全程静默——这里**不再**有「拉起主界面 / 跳识别中页」的
  /// 回调，采集与上传在后台完成，「当前任务」页与通知栏自然更新。
  void Function({required int imageCount, String? sessionId})? onTaskSubmitted;

  /// 是否正在处理一次截屏（UI 用来提示「已有任务在进行」）。
  bool get busy => _busy;

  /// App 生命周期状态（前台时直接跳结果页，后台发通知）。
  bool appInBackground = false;

  static const _channel = MethodChannel('quizsync/capture');

  bool _busy = false;

  /// 多页会话上下文：开始多页时锁定的配对与合集。
  PairingInfo? _mpPairing;
  ApiClient? _mpApi;
  String? _mpCollectionId;

  late final MultiPageCapture multiPage;

  /// 页面销毁时解除 channel 监听。
  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  AndroidCaptureController({
    required this.app,
    required this.captureSource,
    required this.onResultReady,
    required this.onMessage,
  }) {
    multiPage = MultiPageCapture(
      limitOf: () => app.settings.app.multiPageLimit,
      capturePage: _capturePage,
      uploadPage: _uploadPage,
      submitPages: _submitPages,
      onMessage: _notify,
      onStateChanged: (active, pages) => CaptureBridgeCalls.setBallMode(
          active: active, pages: pages),
    );
    try {
      _channel.setMethodCallHandler(_onPlatformCall);
    } catch (_) {
      // 测试环境（无 binding）下无法挂监听，忽略。
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'ball_action':
        final action = call.arguments?.toString() ?? '';
        switch (action) {
          // 短按：非多页 = 单图识别；多页中 = 结束并提交已截取的页。
          case 'capture':
            await onBallTap();
            break;
          // 长按：进入 / 累加多页（每页立即上传）。
          case 'capture_long':
            await onBallLongPress();
            break;
          // 'hidden'：悬浮球已在原生侧隐藏（通知栏保留恢复入口），无需处理。
        }
        break;
      case 'session_lost':
        _notify('截屏会话已失效，下次截屏时需要重新授权');
        break;
    }
    return null;
  }

  // ------------------------------------------------------------
  // 手势入口（用户需求 11）
  // ------------------------------------------------------------

  /// 短按：非多页模式 = 单图识别；多页模式 = 结束并识别已截取的页。
  Future<CaptureResult> onBallTap() async {
    if (_busy) {
      _notify('已有任务在进行中，请稍候');
      return const CaptureResult.failed('已有任务在进行中');
    }
    if (multiPage.active) {
      _busy = true;
      try {
        final outcome = await multiPage.tapToFinish();
        return outcome.result ?? const CaptureResult.failed('多页识别已结束');
      } finally {
        _busy = false;
      }
    }
    return captureAndUpload();
  }

  /// 长按：开始或累加多页；到上限自动提交（提示由状态机给出）。
  Future<CaptureResult> onBallLongPress() async {
    if (_busy) {
      _notify('已有任务在进行中，请稍候');
      return const CaptureResult.failed('已有任务在进行中');
    }
    if (!multiPage.active) {
      final blocked = await _prepareMultiPage();
      if (blocked != null) return blocked;
    }
    _busy = true;
    try {
      final outcome = await multiPage.longPress();
      if (outcome.event == MultiPageEvent.captureFailed) {
        return const CaptureResult.failed('截屏失败');
      }
      if (outcome.event == MultiPageEvent.uploadFailed) {
        return const CaptureResult.failed('上传失败，多页识别已取消');
      }
      return outcome.result ?? const CaptureResult.ok(null);
    } finally {
      _busy = false;
    }
  }

  /// 开始多页前的准备：配对 + 主机必须已选合集（用户需求 12）。
  /// 返回非 null 表示被拦下（调用方直接把它当结果返回）。
  Future<CaptureResult?> _prepareMultiPage() async {
    final info = await app.loadPairing();
    if (info == null) {
      _notify('请先与 Windows 端配对');
      return const CaptureResult.failed('请先与 Windows 端配对');
    }
    final api = ApiClient(baseUrl: info.httpBase, token: info.token);
    final probe = await _probeCollection(api);
    if (probe.blocked) {
      _notify(probe.message!);
      return CaptureResult.failed(probe.message!);
    }
    _mpPairing = info;
    _mpApi = api;
    _mpCollectionId = probe.collectionId;
    return null;
  }

  // ------------------------------------------------------------
  // 单图路径
  // ------------------------------------------------------------

  /// 悬浮球单击主通路（也用于相册选图前的入口检查）。返回流程结果。
  Future<CaptureResult> captureAndUpload({PairingInfo? pairing}) async {
    if (_busy) {
      _notify('已有任务在进行中，请稍候');
      return const CaptureResult.failed('已有任务在进行中');
    }
    final info = pairing ?? await app.loadPairing();
    if (info == null) {
      _notify('请先与 Windows 端配对');
      return const CaptureResult.failed('请先与 Windows 端配对');
    }
    final api = ApiClient(baseUrl: info.httpBase, token: info.token);

    // 用户需求 12：发起识别前必须确认主机已选合集，否则不上传。
    final probe = await _probeCollection(api);
    if (probe.blocked) {
      _notify(probe.message!);
      return CaptureResult.failed(probe.message!);
    }

    _busy = true;
    return _runCaptureAndUpload(info, api, probe.collectionId);
  }

  Future<CaptureResult> _runCaptureAndUpload(
      PairingInfo info, ApiClient api, String? collectionId) async {
    String? jpegHash;
    try {
      final captured = await _captureWithAuth();
      if (captured.bytes == null) {
        _notify(captured.error!);
        return CaptureResult.failed(captured.error!);
      }
      final jpeg = captured.bytes!;
      jpegHash = sha256Hex(jpeg);
      onTaskSubmitted?.call(imageCount: 1);
      final outcome = await uploadAndAnalyze(
        api,
        app.repo,
        jpeg,
        deviceId: app.repo.deviceId,
        // 必须落盘：否则离线补跑时找不到原始图片，队列会永远卡住。
        saveFile: saveImageFile,
        collectionId: collectionId,
      );
      if (outcome.ok) {
        await _afterSuccess(outcome.sessionId!);
        return CaptureResult.ok(outcome.sessionId);
      }
      _notify('分析失败：${outcome.errorMessage ?? outcome.errorCode}');
      return CaptureResult.failed(
          outcome.errorMessage ?? outcome.errorCode ?? '分析失败');
    } on ApiClientException catch (e) {
      if (e.code == 'revoked') {
        await app.clearPairing();
        _notify('已解除配对，请重新扫码');
        return const CaptureResult.failed('已解除配对，请重新扫码');
      }
      if (isNoActiveCollection(e)) {
        // 用户需求 12：409 与本地判断同一句文案，不静默失败。
        _notify(kNoActiveCollectionMessage);
        return const CaptureResult.failed(kNoActiveCollectionMessage);
      }
      // 主机不在线等网络问题 → 入离线队列，等上线后自动补跑。
      final queued = await _enqueueOrReport(jpegHash, collectionId: collectionId);
      if (queued == true) {
        _notify('Windows 不在线，已排队，上线后自动分析');
        return const CaptureResult.failed('Windows 不在线，已排队，上线后自动分析');
      }
      if (queued == null) return const CaptureResult.failed(_kQueueFullMessage);
      _notify('上传失败：${e.message}');
      return CaptureResult.failed('上传失败：${e.message}');
    } catch (_) {
      final queued = await _enqueueOrReport(jpegHash, collectionId: collectionId);
      if (queued == true) {
        _notify('Windows 不在线，已排队，上线后自动分析');
        return const CaptureResult.failed('Windows 不在线，已排队，上线后自动分析');
      }
      if (queued == null) return const CaptureResult.failed(_kQueueFullMessage);
      _notify('Windows 不在线');
      return const CaptureResult.failed('Windows 不在线');
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------
  // 多页路径
  // ------------------------------------------------------------

  /// 多页模式下截一页。
  Future<Uint8List?> _capturePage() async {
    final captured = await _captureWithAuth();
    return captured.bytes;
  }

  /// 多页模式下上传一页：立即上传（用户需求 11），返回主机 hash。
  /// 同时落盘 + 落 images 表，离线补跑时能取到原图。
  Future<String?> _uploadPage(Uint8List jpeg) async {
    final api = _mpApi;
    if (api == null) return null;
    final hash = sha256Hex(jpeg);
    try {
      await app.repo.upsertImage(ImageMeta(
        hash: hash,
        size: jpeg.length,
        mime: 'image/jpeg',
        createdAt: nowMs(),
        uploadedBy: app.repo.deviceId,
      ));
      final saver = saveImageFile;
      if (saver != null) {
        try {
          await saver(hash, jpeg);
        } catch (_) {}
      }
      final up = await api.uploadImage(jpeg);
      return up.imageHash;
    } catch (_) {
      return null;
    }
  }

  /// 多页提交：一次任务带 N 张图片。
  Future<CaptureResult> _submitPages(List<String> hashes) async {
    final api = _mpApi;
    final collectionId = _mpCollectionId;
    final pairing = _mpPairing;
    _mpApi = null;
    _mpPairing = null;
    _mpCollectionId = null;
    if (api == null || pairing == null) {
      return const CaptureResult.failed('配对信息已失效，请重新扫码');
    }
    onTaskSubmitted?.call(imageCount: hashes.length);
    return _runSubmitPages(api, hashes, collectionId);
  }

  Future<CaptureResult> _runSubmitPages(
      ApiClient api, List<String> hashes, String? collectionId) async {
    try {
      final outcome = await createMultiPageTaskAndAnalyze(
        api,
        app.repo,
        hashes,
        deviceId: app.repo.deviceId,
        collectionId: collectionId,
      );
      if (outcome.ok) {
        await _afterSuccess(outcome.sessionId!);
        return CaptureResult.ok(outcome.sessionId);
      }
      _notify('分析失败：${outcome.errorMessage ?? outcome.errorCode}');
      return CaptureResult.failed(
          outcome.errorMessage ?? outcome.errorCode ?? '分析失败');
    } on ApiClientException catch (e) {
      if (e.code == 'revoked') {
        await app.clearPairing();
        _notify('已解除配对，请重新扫码');
        return const CaptureResult.failed('已解除配对，请重新扫码');
      }
      if (isNoActiveCollection(e)) {
        _notify(kNoActiveCollectionMessage);
        return const CaptureResult.failed(kNoActiveCollectionMessage);
      }
      final queued = await _enqueueOrReport(
          hashes.isEmpty ? null : hashes.first,
          imageHashes: hashes,
          collectionId: collectionId);
      if (queued == true) {
        _notify('Windows 不在线，已把 ${hashes.length} 页排队，上线后自动分析');
        return CaptureResult.failed('Windows 不在线，已排队，上线后自动分析');
      }
      if (queued == null) return const CaptureResult.failed(_kQueueFullMessage);
      _notify('上传失败：${e.message}');
      return CaptureResult.failed('上传失败：${e.message}');
    } catch (_) {
      final queued = await _enqueueOrReport(
          hashes.isEmpty ? null : hashes.first,
          imageHashes: hashes,
          collectionId: collectionId);
      if (queued == true) {
        _notify('Windows 不在线，已排队，上线后自动分析');
        return const CaptureResult.failed('Windows 不在线，已排队，上线后自动分析');
      }
      if (queued == null) return const CaptureResult.failed(_kQueueFullMessage);
      _notify('Windows 不在线');
      return const CaptureResult.failed('Windows 不在线');
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------
  // 公共部分
  // ------------------------------------------------------------

  /// 授权检查 + 截屏。返回 (字节, 失败原因)。
  Future<({Uint8List? bytes, String? error})> _captureWithAuth() async {
    try {
      final availability = await captureSource.availability();
      if (!availability.any) {
        final granted = await captureSource.requestAuthorization();
        if (!granted) {
          return (bytes: null, error: '未授予屏幕录制权限，无法截屏');
        }
      }
      final jpeg = await captureSource.capture();
      if (jpeg == null) {
        return (
          bytes: null,
          error: '截屏失败（该应用可能禁止截屏），可改用「从相册选图」'
        );
      }
      return (bytes: jpeg, error: null);
    } catch (e) {
      return (bytes: null, error: '截屏失败：$e');
    }
  }

  /// 发起识别前确认主机已选合集（用户需求 12）。
  /// 连不上主机不算「被拦下」——那属于「主机不在线」，由后面的离线队列兜底。
  Future<({bool blocked, String? message, String? collectionId})>
      _probeCollection(ApiClient api) async {
    try {
      final info = await api.fetchInfo();
      if (!info.hasActiveCollection) {
        return (
          blocked: true,
          message: kNoActiveCollectionMessage,
          collectionId: null
        );
      }
      return (blocked: false, message: null, collectionId: info.activeCollectionId);
    } on ApiClientException {
      return (blocked: false, message: null, collectionId: null);
    }
  }

  /// 成功后的统一收尾：用户在别的应用里时发通知（用户需求 3：
  /// 不再跳任何界面，前台只靠「当前任务」页自然更新）。
  Future<void> _afterSuccess(String sessionId) async {
    if (appInBackground) {
      final questions = await app.repo.questionsOfSession(sessionId);
      final title = questions.isEmpty
          ? '识别完成'
          // 用户需求 3：自绘标题也要用「序号 + 识别到的题号」。
          : '${questions.first.displayTitle} · 答案 ${_answerBrief(questions.first)}';
      await CaptureBridgeCalls.showResultNotification(title, '点击查看结果');
    }
    onResultReady(sessionId);
  }

  /// 把「主机没接住」的图片放入离线队列。
  /// 没有图片 hash 或图片没落盘时返回 false（不假装排队成功）。
  Future<bool> _enqueueOffline(
    String? hash, {
    List<String>? imageHashes,
    String? collectionId,
  }) async {
    if (hash == null) return false;
    try {
      final meta = await app.repo.getImage(hash);
      if (meta?.localPath == null) return false; // 补跑必须能从磁盘取到原图
      await app.queue.enqueue(
        imageHash: hash,
        sourceDevice: app.repo.deviceId,
        imageHashes: imageHashes,
        collectionId: collectionId,
      );
      return true;
    } on QueueFullException {
      // M47：队满不是「网络问题」，不能和别的异常一起吞掉 —— 原来调用方一律回
      // 「上传失败：<网络错误>」，用户永远看不到「离线队列已满（20）…」这句
      // （相册路径是对的，见 home_page 的 on QueueFullException）。
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// 入离线队列，并在**队满**时给一句真话。
  ///
  /// 返回 `true` = 已排队；`false` = 排不进去（原图不在磁盘上）；`null` = 队满
  /// （提示已经发过，调用方直接返回失败即可）。
  Future<bool?> _enqueueOrReport(
    String? hash, {
    List<String>? imageHashes,
    String? collectionId,
  }) async {
    try {
      return await _enqueueOffline(hash,
          imageHashes: imageHashes, collectionId: collectionId);
    } on QueueFullException catch (e) {
      _notify('$e');
      return null;
    }
  }

  static const String _kQueueFullMessage = '离线队列已满，请等 Windows 上线后重试';

  /// 桌面/测试环境没有平台实现时静默忽略；后台时用系统 Toast 提示
  /// （多页手势的用户多半正在别的应用里看题，SnackBar 他看不到）。
  void _notify(String message) {
    if (appInBackground) {
      CaptureBridgeCalls.showToast(message);
    }
    onMessage(message);
  }

  String _answerBrief(Question q) {
    if (q.choice.isNotEmpty) return q.choice.join('');
    final t = q.answerText;
    if (t == null || t.isEmpty) return '-';
    return t.length > 8 ? '${t.substring(0, 8)}…' : t;
  }
}
