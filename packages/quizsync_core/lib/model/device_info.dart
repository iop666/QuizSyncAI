/// 已配对设备 / 已知节点（`data-model.md` devices 表）。
class DeviceInfo {
  final String deviceId;
  final String name;

  /// 'windows' | 'android'
  final String platform;

  /// 仅 Windows 存：token 的 sha256；Android 存 null。
  final String? tokenHash;
  final int pairedAt;
  final int? lastSeenAt;

  /// 非空表示已吊销。
  final int? revokedAt;
  final String? appVersion;

  const DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.platform,
    this.tokenHash,
    required this.pairedAt,
    this.lastSeenAt,
    this.revokedAt,
    this.appVersion,
  });

  bool get isRevoked => revokedAt != null;

  DeviceInfo copyWith({
    String? name,
    int? lastSeenAt,
    int? revokedAt,
    String? appVersion,
  }) =>
      DeviceInfo(
        deviceId: deviceId,
        name: name ?? this.name,
        platform: platform,
        tokenHash: tokenHash,
        pairedAt: pairedAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        revokedAt: revokedAt ?? this.revokedAt,
        appVersion: appVersion ?? this.appVersion,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'platform': platform,
        'paired_at': pairedAt,
        'last_seen_at': lastSeenAt,
        'revoked_at': revokedAt,
        'app_version': appVersion,
        // token_hash 绝不出现在协议 JSON 里。
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        deviceId: json['device_id'].toString(),
        name: json['name']?.toString() ?? '',
        platform: json['platform']?.toString() ?? 'android',
        pairedAt: (json['paired_at'] as num?)?.toInt() ?? 0,
        lastSeenAt: (json['last_seen_at'] as num?)?.toInt(),
        revokedAt: (json['revoked_at'] as num?)?.toInt(),
        appVersion: json['app_version']?.toString(),
      );

  @override
  String toString() => 'DeviceInfo($deviceId $name/$platform)';
}
