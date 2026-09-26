/// 任务合集（用户需求 8/9）：一次任务的全部识别记录归入一个合集。
/// 字段与 `data-model.md` 的 `collections` 表一一对应。
class Collection {
  final String collectionId;
  final String name;

  /// 逐字段写入时钟 `{field: {"l": lamport, "d": deviceId}}`。
  final Map<String, Map<String, dynamic>> fieldClocks;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final int? deletedAt;

  const Collection({
    required this.collectionId,
    required this.name,
    this.fieldClocks = const {},
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    this.lamport = 0,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  Collection copyWith({
    String? name,
    Map<String, Map<String, dynamic>>? fieldClocks,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    int? deletedAt,
  }) =>
      Collection(
        collectionId: collectionId,
        name: name ?? this.name,
        fieldClocks: fieldClocks ?? this.fieldClocks,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
        lamport: lamport ?? this.lamport,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'collection_id': collectionId,
        'name': name,
        'field_clocks_json': fieldClocks,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'lamport': lamport,
        'deleted_at': deletedAt,
      };

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
        collectionId: json['collection_id'].toString(),
        name: json['name']?.toString() ?? '',
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
  String toString() => 'Collection($collectionId "$name")';
}
