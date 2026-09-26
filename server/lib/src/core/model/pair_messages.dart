import 'dart:math';

/// `POST /api/v1/pair` 请求体（protocol.md 2.2）。
class PairRequest {
  final String code;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;

  const PairRequest({
    required this.code,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': appVersion,
      };

  factory PairRequest.fromJson(Map<String, dynamic> json) => PairRequest(
        code: json['code']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        deviceName: json['device_name']?.toString() ?? '',
        platform: json['platform']?.toString() ?? 'android',
        appVersion: json['app_version']?.toString() ?? '',
      );

  /// 字段完整性校验（服务端 400 invalid_request 的判定）。
  bool get isValid =>
      code.isNotEmpty &&
      deviceId.isNotEmpty &&
      deviceName.isNotEmpty &&
      platform.isNotEmpty;
}

/// `POST /api/v1/pair` 成功响应。
class PairResponse {
  final String token;
  final String serverDeviceId;
  final String serverName;
  final int protocolVersion;

  const PairResponse({
    required this.token,
    required this.serverDeviceId,
    required this.serverName,
    required this.protocolVersion,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'server_device_id': serverDeviceId,
        'server_name': serverName,
        'protocol_version': protocolVersion,
      };

  factory PairResponse.fromJson(Map<String, dynamic> json) => PairResponse(
        token: json['token']?.toString() ?? '',
        serverDeviceId: json['server_device_id']?.toString() ?? '',
        serverName: json['server_name']?.toString() ?? '',
        protocolVersion: (json['protocol_version'] as num?)?.toInt() ?? 0,
      );
}

/// `GET /api/v1/info` 响应（protocol.md 3.1）。
class ServerInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final int protocolVersion;
  final String appVersion;
  final bool aiConfigured;
  final List<String> capabilities;

  /// 主机当前选中的合集（用户需求 12）：null = 主机还没选合集，
  /// 此时安卓端不允许发起识别（服务端也会用 409 兜底）。
  final String? activeCollectionId;
  final String? activeCollectionName;

  const ServerInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.protocolVersion,
    required this.appVersion,
    required this.aiConfigured,
    required this.capabilities,
    this.activeCollectionId,
    this.activeCollectionName,
  });

  bool get hasActiveCollection =>
      activeCollectionId != null && activeCollectionId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'protocol_version': protocolVersion,
        'app_version': appVersion,
        'ai_configured': aiConfigured,
        'active_collection_id': activeCollectionId,
        'active_collection_name': activeCollectionName,
        'capabilities': List<String>.from(capabilities),
      };

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        deviceId: json['device_id']?.toString() ?? '',
        deviceName: json['device_name']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
        protocolVersion: (json['protocol_version'] as num?)?.toInt() ?? 0,
        appVersion: json['app_version']?.toString() ?? '',
        aiConfigured: json['ai_configured'] == true,
        activeCollectionId: json['active_collection_id']?.toString(),
        activeCollectionName: json['active_collection_name']?.toString(),
        capabilities: json['capabilities'] is List
            ? (json['capabilities'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

/// 统一错误响应（protocol.md 3.5）。
class ApiError {
  final String code;
  final String message;
  final int? retryAfterSeconds;

  const ApiError({
    required this.code,
    required this.message,
    this.retryAfterSeconds,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'retry_after_seconds': retryAfterSeconds,
      };

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
        code: json['code']?.toString() ?? 'internal',
        message: json['message']?.toString() ?? '',
        retryAfterSeconds: (json['retry_after_seconds'] as num?)?.toInt(),
      );
}

/// 生成 6 位数字配对码。
String generatePairingCode() {
  final rng = Random.secure();
  return (100000 + rng.nextInt(900000)).toString();
}

/// 生成 64 位 hex 的长期 token（32 字节随机）。
String generateTokenHex() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
