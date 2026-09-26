import 'package:flutter/services.dart';

/// 采集源抽象（M5 任务 7）：Dart 层不接触 MediaProjection API。
abstract class CaptureSource {
  /// JPEG 字节；null = 不可用（需授权 / 会话失效）。
  Future<Uint8List?> capture();

  /// 各路径可用性。
  Future<CaptureAvailability> availability();

  /// 请求 MediaProjection 系统授权（首次弹一次框）。
  Future<bool> requestAuthorization();
}

class CaptureAvailability {
  final bool main;
  final bool accessibility;
  final bool sessionLost;
  final bool overlayGranted;

  const CaptureAvailability({
    this.main = false,
    this.accessibility = false,
    this.sessionLost = false,
    this.overlayGranted = false,
  });

  bool get any => main || accessibility;
}

/// 真机实现：走 MethodChannel（Kotlin 侧 CaptureBridge）。
class MethodChannelCaptureSource implements CaptureSource {
  static const _channel = MethodChannel('quizsync/capture');

  @override
  Future<Uint8List?> capture() async {
    try {
      final bytes = await _channel.invokeMethod<List<int>>('captureScreen');
      if (bytes == null) return null;
      return Uint8List.fromList(bytes);
    } on PlatformException catch (e) {
      if (e.code == 'capture_failed' && e.message == 'session_lost') {
        return null; // 会话失效：由 availability 的 sessionLost 引导
      }
      if (e.code == 'capture_failed') return null; // 黑图/无帧（FLAG_SECURE 等）
      rethrow;
    } catch (_) {
      // 平台通道不可用（无 binding / 非 Android）：按「取不到帧」处理。
      return null;
    }
  }

  @override
  Future<CaptureAvailability> availability() async {
    try {
      final map = await _channel
          .invokeMapMethod<String, dynamic>('isCaptureAvailable');
      if (map == null) return const CaptureAvailability();
      return CaptureAvailability(
        main: map['main'] == true,
        accessibility: map['accessibility'] == true,
        sessionLost: map['sessionLost'] == true,
        overlayGranted: map['overlayGranted'] == true,
      );
    } catch (_) {
      // 平台通道未就绪（测试 / 非 Android / 无 binding）：按「都不可用」处理。
      // 原来只 catch PlatformException + MissingPluginException，纯 Dart
      // 单测里会撞上 ServicesBinding 的 binding 断言并变成未处理异常。
      return const CaptureAvailability();
    }
  }

  @override
  Future<bool> requestAuthorization() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestProjectionAuthorization') ??
          false;
    } catch (_) {
      return false;
    }
  }
}

/// 测试假实现：返回固定 JPEG 字节。
class FakeCaptureSource implements CaptureSource {
  final Uint8List jpeg;
  final CaptureAvailability fakeAvailability;
  int captureCount = 0;

  FakeCaptureSource(this.jpeg,
      {this.fakeAvailability = const CaptureAvailability(main: true)});

  @override
  Future<Uint8List?> capture() async {
    captureCount++;
    return jpeg;
  }

  @override
  Future<CaptureAvailability> availability() async => fakeAvailability;

  @override
  Future<bool> requestAuthorization() async => true;
}

/// 权限授予状态的快照（识别模块设置页用）。
class PermissionStatus {
  final bool notifications;
  final bool overlay;
  final bool battery;
  final bool accessibility;

  const PermissionStatus({
    required this.notifications,
    required this.overlay,
    required this.battery,
    required this.accessibility,
  });
}

/// 平台工具：悬浮球显隐 / 通知 / 跳设置。
///
/// 全部是「通知平台」的尽力而为调用：任何失败（无 binding / 桌面 /
/// 测试环境 / channel 未挂载）都静默忽略，绝不反过来掀翻界面。
class CaptureBridgeCalls {
  static const _channel = MethodChannel('quizsync/capture');

  static Future<void> setCaptureMode(String mode) =>
      _tryInvoke('setCaptureMode', {'mode': mode});

  /// 多页模式状态（用户需求 11）：推给原生悬浮球换色/换提示，
  /// **业务判断仍在 Dart**，这里只是让球能显示「正在收集第 N 页」。
  static Future<void> setBallMode({required bool active, required int pages}) =>
      _tryInvoke('setBallMode', {'active': active, 'pages': pages});

  /// 悬浮球外观（用户需求 11）：alpha 0.3–1.0，尺寸 dp。
  static Future<void> setBallAppearance(
          {required double opacity, required double sizeDp}) =>
      _tryInvoke('setBallAppearance', {'opacity': opacity, 'size': sizeDp});

  /// 系统 Toast：悬浮球在其他应用上时 SnackBar 用户看不到。
  static Future<void> showToast(String text) =>
      _tryInvoke('showToast', {'text': text});

  /// 回读平台侧真实状态（截屏路径 / 悬浮球是否显示）。
  /// 取不到时返回 null，调用方保持自己的默认值。
  static Future<({String mode, bool ballVisible})?> captureState() async {
    try {
      final map =
          await _channel.invokeMapMethod<String, dynamic>('getCaptureState');
      if (map == null) return null;
      return (
        mode: map['mode']?.toString() ?? 'main',
        ballVisible: map['ballVisible'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 识别模块设置页用：回读通知/悬浮窗/电池/无障碍的真实授予状态。
  static Future<PermissionStatus?> permissionStatus() async {
    try {
      final map = await _channel
          .invokeMapMethod<String, dynamic>('getPermissionStatus');
      if (map == null) return null;
      return PermissionStatus(
        notifications: map['notifications'] == true,
        overlay: map['overlay'] == true,
        battery: map['battery'] == true,
        accessibility: map['accessibility'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 显示/隐藏悬浮球。返回是否真的显示（false = 悬浮窗权限未授予等）。
  static Future<bool> setBallVisible(bool visible) async {
    try {
      return await _channel
              .invokeMethod<bool>('setBallVisible', {'visible': visible}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 请求通知权限（Android 13+；低版本恒 true）。授予后截屏服务常驻通知可见。
  static Future<bool> requestNotificationPermission() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showResultNotification(String title, String text) =>
      _tryInvoke('showResultNotification', {'title': title, 'text': text});

  static Future<void> openOverlaySettings() =>
      _tryInvoke('openOverlaySettings');

  static Future<void> openNotificationSettings() =>
      _tryInvoke('openNotificationSettings');

  static Future<void> openAccessibilitySettings() =>
      _tryInvoke('openAccessibilitySettings');

  static Future<void> openBatterySettings() =>
      _tryInvoke('openBatterySettings');

  /// 请求相机权限（配对页扫码用，用户需求 7）：**点击「开始使用」后**才调用，
  /// 保证首次进入配对页不会自动调起相机。
  /// 平台侧未就绪（测试 / 非 Android）时返回 false，由调用方给明确提示。
  static Future<bool> requestCameraPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestCameraPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 打开本应用的系统设置页：相机权限被「拒绝且不再询问」后的兜底入口。
  static Future<void> openAppSettings() => _tryInvoke('openAppSettings');

  static Future<void> _tryInvoke(String method,
      [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // 平台侧未就绪：静默忽略。
    }
  }
}
