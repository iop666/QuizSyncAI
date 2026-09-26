/// 会话的一页图片（用户需求 4：多页题目一次识别）。
///
/// `sessions.image_hash` 保留为**第一页**，兼容既有缓存去重与协议字段；
/// 多页顺序由本表的 `ordinal`（0 起）决定。
class SessionImage {
  final String sessionImageId;
  final String sessionId;

  /// 会话内的页序，0 起。
  final int ordinal;
  final String imageHash;

  final Map<String, Map<String, dynamic>> fieldClocks;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final int? deletedAt;

  const SessionImage({
    required this.sessionImageId,
    required this.sessionId,
    required this.ordinal,
    required this.imageHash,
    this.fieldClocks = const {},
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    this.lamport = 0,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  SessionImage copyWith({
    int? ordinal,
    String? imageHash,
    Map<String, Map<String, dynamic>>? fieldClocks,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    int? deletedAt,
  }) =>
      SessionImage(
        sessionImageId: sessionImageId,
        sessionId: sessionId,
        ordinal: ordinal ?? this.ordinal,
        imageHash: imageHash ?? this.imageHash,
        fieldClocks: fieldClocks ?? this.fieldClocks,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
        lamport: lamport ?? this.lamport,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'session_image_id': sessionImageId,
        'session_id': sessionId,
        'ordinal': ordinal,
        'image_hash': imageHash,
        'field_clocks_json': fieldClocks,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'lamport': lamport,
        'deleted_at': deletedAt,
      };

  factory SessionImage.fromJson(Map<String, dynamic> json) => SessionImage(
        sessionImageId: json['session_image_id'].toString(),
        sessionId: json['session_id']?.toString() ?? '',
        ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
        imageHash: json['image_hash']?.toString() ?? '',
        fieldClocks: _parseClocks(json['field_clocks_json']),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
        updatedBy: json['updated_by']?.toString() ?? '',
        lamport: (json['lamport'] as num?)?.toInt() ?? 0,
        deletedAt: (json['deleted_at'] as num?)?.toInt(),
      );

  static Map<String, Map<String, dynamic>> _parseClocks(dynamic raw) {
    if (raw is Map) {
      return raw.map(
          (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    }
    return const {};
  }

  @override
  String toString() {
    // 短 hash（单测里的 'p1' 这种）不能让诊断信息本身抛 RangeError：
    // 断言失败时打印列表会把真正的失败原因盖掉（2026-09-26 实测）。
    final short =
        imageHash.length <= 8 ? imageHash : imageHash.substring(0, 8);
    return 'SessionImage($sessionId #$ordinal $short)';
  }
}
