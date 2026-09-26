/// 同步操作日志（`data-model.md` sync_ops 表）。同步的唯一载体。
enum SyncEntity {
  session('session'),
  question('question'),
  image('image'),
  device('device'),

  /// 任务合集（用户需求 8）。
  collection('collection'),

  /// 会话的页图片（用户需求 4）。
  sessionImage('session_image'),
  snapshot('snapshot');

  final String wire;
  const SyncEntity(this.wire);

  static SyncEntity parse(String? raw) => SyncEntity.values.firstWhere(
        (e) => e.wire == raw,
        orElse: () => SyncEntity.snapshot,
      );

  @override
  String toString() => wire;
}

enum SyncOpType {
  upsert('upsert'),
  delete('delete');

  final String wire;
  const SyncOpType(this.wire);

  static SyncOpType parse(String? raw) => SyncOpType.values.firstWhere(
        (t) => t.wire == raw,
        orElse: () => SyncOpType.upsert,
      );

  @override
  String toString() => wire;
}

class SyncOp {
  /// UUID v4；重复 op 按 op_id 忽略。
  final String opId;

  /// 产生该 op 的设备。
  final String deviceId;
  final int lamport;
  final SyncEntity entity;
  final String entityId;
  final SyncOpType opType;

  /// 只含本次真正改动的字段（字段级 LWW 的依据）。
  /// 字段名用 DB 列名（snake_case），值为该列的目标值。
  final Map<String, dynamic> fields;

  final int createdAt;

  const SyncOp({
    required this.opId,
    required this.deviceId,
    required this.lamport,
    required this.entity,
    required this.entityId,
    required this.opType,
    required this.fields,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'device_id': deviceId,
        'lamport': lamport,
        'entity': entity.wire,
        'entity_id': entityId,
        'op_type': opType.wire,
        'fields_json': fields,
        'created_at': createdAt,
      };

  factory SyncOp.fromJson(Map<String, dynamic> json) => SyncOp(
        opId: json['op_id'].toString(),
        deviceId: json['device_id'].toString(),
        lamport: (json['lamport'] as num?)?.toInt() ?? 0,
        entity: SyncEntity.parse(json['entity']?.toString()),
        entityId: json['entity_id'].toString(),
        opType: SyncOpType.parse(json['op_type']?.toString()),
        fields: json['fields_json'] is Map
            ? Map<String, dynamic>.from(json['fields_json'] as Map)
            : const {},
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'SyncOp($opId ${entity.wire}/$entityId ${opType.wire} l=$lamport d=$deviceId fields=${fields.keys.toList()})';
}
