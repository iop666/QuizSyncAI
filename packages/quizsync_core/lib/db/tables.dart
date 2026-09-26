import 'package:drift/drift.dart';

import 'converters.dart';

/// `data-model.md` 第 1 节全部表的 drift 定义。
/// 列名由 drift 自动转 snake_case，与契约一致。

@DataClassName('DeviceRow')
class Devices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();

  /// 仅 Windows 存：token 的 sha256；Android 存 NULL。
  TextColumn get tokenHash => text().nullable()();
  IntColumn get pairedAt => integer()();
  IntColumn get lastSeenAt => integer().nullable()();

  /// 非空表示已吊销。
  IntColumn get revokedAt => integer().nullable()();
  TextColumn get appVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {deviceId};
}

@DataClassName('ImageRow')
@TableIndex(name: 'idx_images_created', columns: {#createdAt})
class Images extends Table {
  /// sha256(压缩后字节)。
  TextColumn get hash => text()();

  IntColumn get size => integer()();
  TextColumn get mime => text()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();

  /// 本机文件路径；该端没有文件时为 NULL（可后台补传）。
  TextColumn get localPath => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get uploadedBy => text()();

  @override
  Set<Column> get primaryKey => {hash};

  @override
  String get tableName => 'images';

  @override
  List<String> get customConstraints => [];
}

/// 任务合集（用户需求 8）：一次任务的全部识别记录归入一个合集。
/// Windows 首次启动必须新建/选择合集后才能开始任务。
@TableIndex(name: 'idx_collections_created', columns: {#createdAt})
@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get collectionId => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedBy => text()();
  IntColumn get lamport => integer().withDefault(const Constant(0))();
  TextColumn get fieldClocksJson =>
      text().map(const FieldClocksConverter()).withDefault(const Constant('{}'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {collectionId};
}

/// 会话的一页图片（用户需求 4：多页题目一次识别）。
@TableIndex(name: 'idx_session_images_session', columns: {#sessionId, #ordinal})
@DataClassName('SessionImageRow')
class SessionImages extends Table {
  TextColumn get sessionImageId => text()();
  TextColumn get sessionId => text()();

  /// 会话内的页序，0 起。
  IntColumn get ordinal => integer()();
  TextColumn get imageHash => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedBy => text()();
  IntColumn get lamport => integer().withDefault(const Constant(0))();
  TextColumn get fieldClocksJson =>
      text().map(const FieldClocksConverter()).withDefault(const Constant('{}'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionImageId};

  @override
  String get tableName => 'session_images';
}

/// 会话 = 一次识别 = 一条历史记录。
@TableIndex(name: 'idx_sessions_created', columns: {#createdAt})
@TableIndex(name: 'idx_sessions_hash', columns: {#imageHash})
@TableIndex(name: 'idx_sessions_status', columns: {#status})
@TableIndex(name: 'idx_sessions_collection', columns: {#collectionId})
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get sessionId => text()();

  /// 发起端生成的幂等 id。
  TextColumn get taskId => text().nullable()();

  /// 所属合集（用户需求 8）。历史数据为 NULL，显示为「未分类」。
  TextColumn get collectionId => text().nullable()();

  /// 多页识别的**第一页**；页序见 session_images。
  TextColumn get imageHash => text()();
  TextColumn get sourceDevice => text()();

  /// queued|analyzing|done|failed|cancelled
  TextColumn get status => text()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get aiProvider => text().nullable()();
  TextColumn get aiModel => text().nullable()();
  TextColumn get promptVersion => text().nullable()();

  /// 解析失败时保留原文。
  TextColumn get rawResponse => text().nullable()();
  BoolColumn get cached => boolean().withDefault(const Constant(false))();
  IntColumn get questionCount => integer().withDefault(const Constant(0))();
  IntColumn get latencyMs => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedBy => text()();
  IntColumn get lamport => integer().withDefault(const Constant(0))();

  /// 逐字段写入时钟，见 data-model.md 2.2。
  TextColumn get fieldClocksJson =>
      text().map(const FieldClocksConverter()).withDefault(const Constant('{}'))();

  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

@TableIndex(name: 'idx_questions_session', columns: {#sessionId, #ordinal})
@TableIndex(name: 'idx_questions_stem', columns: {#stem})
@DataClassName('QuestionRow')
class Questions extends Table {
  TextColumn get questionId => text()();
  TextColumn get sessionId => text()();

  /// 会话内的顺序，0 起。
  IntColumn get ordinal => integer()();
  TextColumn get questionNo => text().nullable()();
  TextColumn get stem => text()();

  /// 阅读材料 / 文章原文（用户反馈 15）：只有阅读类题目才有，端侧默认折叠。
  /// 空串 = 无附属材料（绝大多数题目）。
  TextColumn get material => text().withDefault(const Constant(''))();

  /// single|multi|judge|blank|subjective
  TextColumn get type => text()();

  TextColumn get optionsJson =>
      text().map(const OptionsListConverter()).withDefault(const Constant('[]'))();
  TextColumn get choiceJson =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get answerText => text().nullable()();
  TextColumn get analysis => text().withDefault(const Constant(''))();
  RealColumn get confidence => real().withDefault(const Constant(0.5))();
  BoolColumn get needReview => boolean().withDefault(const Constant(false))();
  BoolColumn get answerInImage => boolean().withDefault(const Constant(false))();

  /// 题目不全（用户需求 2）：题干/选项被截断或缺失，卡片加黄框提示。
  BoolColumn get incomplete => boolean().withDefault(const Constant(false))();

  /// 答案是 AI 猜测（用户需求 2）：题干在但选项不全时，AI 推断的答案。
  BoolColumn get answerGuessed => boolean().withDefault(const Constant(false))();
  TextColumn get warningsJson =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();

  /// 字段级 user_edited 标记。
  BoolColumn get analysisEdited => boolean().withDefault(const Constant(false))();
  BoolColumn get answerEdited => boolean().withDefault(const Constant(false))();
  TextColumn get fieldClocksJson =>
      text().map(const FieldClocksConverter()).withDefault(const Constant('{}'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedBy => text()();
  IntColumn get lamport => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {questionId};
}

/// 操作日志：同步的唯一载体。
@TableIndex(name: 'idx_ops_lamport', columns: {#deviceId, #lamport})
@TableIndex(name: 'idx_ops_entity', columns: {#entity, #entityId})
@DataClassName('SyncOpRow')
class SyncOps extends Table {
  /// UUID v4。
  TextColumn get opId => text()();

  /// 产生该 op 的设备（含本机应用并转存的对端 op，保留原 device_id）。
  TextColumn get deviceId => text()();
  IntColumn get lamport => integer()();

  /// 'session' | 'question' | 'image' | 'device' | 'snapshot'
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// 'upsert' | 'delete'
  TextColumn get opType => text()();

  /// 只含变更字段，字段级 LWW 的依据。
  TextColumn get fieldsJson => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {opId};
}

/// 每个对端的同步水位线。
@DataClassName('PeerStateRow')
class PeerStates extends Table {
  TextColumn get peerDeviceId => text()();
  IntColumn get sentLamport => integer().withDefault(const Constant(0))();
  IntColumn get ackedLamport => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {peerDeviceId};

  @override
  String get tableName => 'peer_state';
}

/// 分析任务（离线队列也在其中）。
@TableIndex(name: 'idx_tasks_status', columns: {#status, #createdAt})
@DataClassName('TaskRow')
class Tasks extends Table {
  /// 发起端生成的 UUID v4，保证幂等。
  TextColumn get taskId => text()();
  TextColumn get imageHash => text()();
  TextColumn get sourceDevice => text()();

  /// queued|analyzing|done|failed|cancelled
  TextColumn get status => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get errorCode => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get finishedAt => integer().nullable()();

  /// 离线入队时记下的额外参数（`{"image_hashes": [...], "collection_id": "..."}`）。
  /// 多页识别（用户需求 4）与合集（用户需求 8）都必须在断网重连后原样补跑，
  /// 这两个值没有独立列，统一放这里，避免为一个本地协调表再加两列。
  TextColumn get payloadJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {taskId};
}

/// 本机设置（不含密钥）。
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// AI 用量与配额。
@TableIndex(name: 'idx_usage_called', columns: {#calledAt})
@DataClassName('AiUsageRow')
class AiUsage extends Table {
  TextColumn get id => text()();
  IntColumn get calledAt => integer()();
  TextColumn get model => text()();
  TextColumn get promptVersion => text()();
  TextColumn get imageHash => text()();
  BoolColumn get ok => boolean()();
  TextColumn get errorCode => text().nullable()();
  IntColumn get latencyMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'ai_usage';
}
