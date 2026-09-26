import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/device_info.dart';
import '../model/collection.dart';
import '../model/image_meta.dart';
import '../model/option.dart';
import '../model/question.dart';
import '../model/question_type.dart';
import '../model/session.dart';
import '../model/session_image.dart';
import '../model/sync_op.dart';
import '../model/task_state.dart';
import '../sync/field_clocks.dart';
import 'converters.dart';
import 'database.dart';

// ============================================================
// 模型 ↔ drift 行
// ============================================================

Session sessionFromRow(SessionRow r) => Session(
      sessionId: r.sessionId,
      taskId: r.taskId,
      collectionId: r.collectionId,
      imageHash: r.imageHash,
      sourceDevice: r.sourceDevice,
      status: TaskState.parse(r.status),
      errorCode: r.errorCode,
      errorMessage: r.errorMessage,
      aiProvider: r.aiProvider,
      aiModel: r.aiModel,
      promptVersion: r.promptVersion,
      rawResponse: r.rawResponse,
      cached: r.cached,
      questionCount: r.questionCount,
      latencyMs: r.latencyMs,
      fieldClocks: _clocksToRaw(r.fieldClocksJson),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      updatedBy: r.updatedBy,
      lamport: r.lamport,
      deletedAt: r.deletedAt,
    );

Question questionFromRow(QuestionRow r) => Question(
      questionId: r.questionId,
      sessionId: r.sessionId,
      ordinal: r.ordinal,
      questionNo: r.questionNo,
      stem: r.stem,
      material: r.material,
      type: QuestionType.parse(r.type),
      options: r.optionsJson,
      choice: r.choiceJson,
      answerText: r.answerText,
      analysis: r.analysis,
      confidence: r.confidence,
      needReview: r.needReview,
      answerInImage: r.answerInImage,
      incomplete: r.incomplete,
      answerGuessed: r.answerGuessed,
      warnings: r.warningsJson,
      analysisEdited: r.analysisEdited,
      answerEdited: r.answerEdited,
      fieldClocks: _clocksToRaw(r.fieldClocksJson),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      updatedBy: r.updatedBy,
      lamport: r.lamport,
      deletedAt: r.deletedAt,
    );

Collection collectionFromRow(CollectionRow r) => Collection(
      collectionId: r.collectionId,
      name: r.name,
      fieldClocks: _clocksToRaw(r.fieldClocksJson),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      updatedBy: r.updatedBy,
      lamport: r.lamport,
      deletedAt: r.deletedAt,
    );

SessionImage sessionImageFromRow(SessionImageRow r) => SessionImage(
      sessionImageId: r.sessionImageId,
      sessionId: r.sessionId,
      ordinal: r.ordinal,
      imageHash: r.imageHash,
      fieldClocks: _clocksToRaw(r.fieldClocksJson),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      updatedBy: r.updatedBy,
      lamport: r.lamport,
      deletedAt: r.deletedAt,
    );

ImageMeta imageFromRow(ImageRow r) => ImageMeta(
      hash: r.hash,
      size: r.size,
      mime: r.mime,
      width: r.width,
      height: r.height,
      localPath: r.localPath,
      createdAt: r.createdAt,
      uploadedBy: r.uploadedBy,
    );

DeviceInfo deviceFromRow(DeviceRow r) => DeviceInfo(
      deviceId: r.deviceId,
      name: r.name,
      platform: r.platform,
      tokenHash: r.tokenHash,
      pairedAt: r.pairedAt,
      lastSeenAt: r.lastSeenAt,
      revokedAt: r.revokedAt,
      appVersion: r.appVersion,
    );

SyncOp opFromRow(SyncOpRow r) {
  Map<String, dynamic> fields = {};
  try {
    final decoded = jsonDecode(r.fieldsJson);
    if (decoded is Map) fields = Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return SyncOp(
    opId: r.opId,
    deviceId: r.deviceId,
    lamport: r.lamport,
    entity: SyncEntity.parse(r.entity),
    entityId: r.entityId,
    opType: SyncOpType.parse(r.opType),
    fields: fields,
    createdAt: r.createdAt,
  );
}

// ============================================================
// 模型 → SQL 域字段映射（op 的 fields_json 也用这个域）
// ============================================================

Map<String, dynamic> sessionFieldMap(Session s) => {
      'task_id': s.taskId,
      'collection_id': s.collectionId,
      'image_hash': s.imageHash,
      'source_device': s.sourceDevice,
      'status': s.status.wire,
      'error_code': s.errorCode,
      'error_message': s.errorMessage,
      'ai_provider': s.aiProvider,
      'ai_model': s.aiModel,
      'prompt_version': s.promptVersion,
      'raw_response': s.rawResponse,
      'cached': s.cached ? 1 : 0,
      'question_count': s.questionCount,
      'latency_ms': s.latencyMs,
      'created_at': s.createdAt,
      'updated_at': s.updatedAt,
      'updated_by': s.updatedBy,
      'deleted_at': s.deletedAt,
    };

Map<String, dynamic> questionFieldMap(Question q) => {
      'session_id': q.sessionId,
      'ordinal': q.ordinal,
      'question_no': q.questionNo,
      'stem': q.stem,
      'material': q.material,
      'type': q.type.wire,
      'options_json': jsonEncode(q.options.map((o) => o.toJson()).toList()),
      'choice_json': jsonEncode(q.choice),
      'answer_text': q.answerText,
      'analysis': q.analysis,
      'confidence': q.confidence,
      'need_review': q.needReview ? 1 : 0,
      'answer_in_image': q.answerInImage ? 1 : 0,
      'incomplete': q.incomplete ? 1 : 0,
      'answer_guessed': q.answerGuessed ? 1 : 0,
      'warnings_json': jsonEncode(q.warnings),
      'analysis_edited': q.analysisEdited ? 1 : 0,
      'answer_edited': q.answerEdited ? 1 : 0,
      'created_at': q.createdAt,
      'updated_at': q.updatedAt,
      'updated_by': q.updatedBy,
      'deleted_at': q.deletedAt,
    };

Map<String, dynamic> imageFieldMap(ImageMeta m) => {
      'size': m.size,
      'mime': m.mime,
      'width': m.width,
      'height': m.height,
      'local_path': m.localPath,
      'created_at': m.createdAt,
      'uploaded_by': m.uploadedBy,
    };

Map<String, dynamic> deviceFieldMap(DeviceInfo d) => {
      'name': d.name,
      'platform': d.platform,
      'token_hash': d.tokenHash,
      'paired_at': d.pairedAt,
      'last_seen_at': d.lastSeenAt,
      'revoked_at': d.revokedAt,
      'app_version': d.appVersion,
    };

Map<String, dynamic> collectionFieldMap(Collection c) => {
      'name': c.name,
      'created_at': c.createdAt,
      'updated_at': c.updatedAt,
      'updated_by': c.updatedBy,
      'deleted_at': c.deletedAt,
    };

Map<String, dynamic> sessionImageFieldMap(SessionImage s) => {
      'session_id': s.sessionId,
      'ordinal': s.ordinal,
      'image_hash': s.imageHash,
      'created_at': s.createdAt,
      'updated_at': s.updatedAt,
      'updated_by': s.updatedBy,
      'deleted_at': s.deletedAt,
    };

// ============================================================
// SQL 域字段映射 → drift Companion（远端 op 应用时用）
// ============================================================

SessionsCompanion sessionCompanionFromFields(Map<String, dynamic> f) =>
    SessionsCompanion(
      taskId: _v<String?>(f, 'task_id'),
      collectionId: _v<String?>(f, 'collection_id'),
      imageHash: _v<String>(f, 'image_hash'),
      sourceDevice: _v<String>(f, 'source_device'),
      status: _v<String>(f, 'status'),
      errorCode: _v<String?>(f, 'error_code'),
      errorMessage: _v<String?>(f, 'error_message'),
      aiProvider: _v<String?>(f, 'ai_provider'),
      aiModel: _v<String?>(f, 'ai_model'),
      promptVersion: _v<String?>(f, 'prompt_version'),
      rawResponse: _v<String?>(f, 'raw_response'),
      cached: _vBool(f, 'cached'),
      questionCount: _vInt(f, 'question_count'),
      latencyMs: _vIntOrNull(f, 'latency_ms'),
      createdAt: _vInt(f, 'created_at'),
      updatedAt: _vInt(f, 'updated_at'),
      updatedBy: _v<String>(f, 'updated_by'),
      deletedAt: _vIntOrNull(f, 'deleted_at'),
    );

QuestionsCompanion questionCompanionFromFields(Map<String, dynamic> f) =>
    QuestionsCompanion(
      sessionId: _v<String>(f, 'session_id'),
      ordinal: _vInt(f, 'ordinal'),
      questionNo: _v<String?>(f, 'question_no'),
      stem: _v<String>(f, 'stem'),
      material: _vString(f, 'material'),
      type: _v<String>(f, 'type'),
      optionsJson: _vOptions(f, 'options_json'),
      choiceJson: _vStrings(f, 'choice_json'),
      answerText: _v<String?>(f, 'answer_text'),
      analysis: _v<String>(f, 'analysis'),
      confidence: _vDouble(f, 'confidence'),
      needReview: _vBool(f, 'need_review'),
      answerInImage: _vBool(f, 'answer_in_image'),
      incomplete: _vBool(f, 'incomplete'),
      answerGuessed: _vBool(f, 'answer_guessed'),
      warningsJson: _vStrings(f, 'warnings_json'),
      analysisEdited: _vBool(f, 'analysis_edited'),
      answerEdited: _vBool(f, 'answer_edited'),
      createdAt: _vInt(f, 'created_at'),
      updatedAt: _vInt(f, 'updated_at'),
      updatedBy: _v<String>(f, 'updated_by'),
      deletedAt: _vIntOrNull(f, 'deleted_at'),
    );

ImagesCompanion imageCompanionFromFields(Map<String, dynamic> f) =>
    ImagesCompanion(
      size: _vInt(f, 'size'),
      mime: _v<String>(f, 'mime'),
      width: _vIntOrNull(f, 'width'),
      height: _vIntOrNull(f, 'height'),
      localPath: _v<String?>(f, 'local_path'),
      createdAt: _vInt(f, 'created_at'),
      uploadedBy: _v<String>(f, 'uploaded_by'),
    );

DevicesCompanion deviceCompanionFromFields(Map<String, dynamic> f) =>
    DevicesCompanion(
      name: _v<String>(f, 'name'),
      platform: _v<String>(f, 'platform'),
      tokenHash: _v<String?>(f, 'token_hash'),
      pairedAt: _vInt(f, 'paired_at'),
      lastSeenAt: _vIntOrNull(f, 'last_seen_at'),
      revokedAt: _vIntOrNull(f, 'revoked_at'),
      appVersion: _v<String?>(f, 'app_version'),
    );

CollectionsCompanion collectionCompanionFromFields(Map<String, dynamic> f) =>
    CollectionsCompanion(
      name: _v<String>(f, 'name'),
      createdAt: _vInt(f, 'created_at'),
      updatedAt: _vInt(f, 'updated_at'),
      updatedBy: _v<String>(f, 'updated_by'),
      deletedAt: _vIntOrNull(f, 'deleted_at'),
    );

SessionImagesCompanion sessionImageCompanionFromFields(
        Map<String, dynamic> f) =>
    SessionImagesCompanion(
      sessionId: _v<String>(f, 'session_id'),
      ordinal: _vInt(f, 'ordinal'),
      imageHash: _v<String>(f, 'image_hash'),
      createdAt: _vInt(f, 'created_at'),
      updatedAt: _vInt(f, 'updated_at'),
      updatedBy: _v<String>(f, 'updated_by'),
      deletedAt: _vIntOrNull(f, 'deleted_at'),
    );

SyncOpsCompanion opToCompanion(SyncOp op) => SyncOpsCompanion(
      opId: Value(op.opId),
      deviceId: Value(op.deviceId),
      lamport: Value(op.lamport),
      entity: Value(op.entity.wire),
      entityId: Value(op.entityId),
      opType: Value(op.opType.wire),
      fieldsJson: Value(jsonEncode(op.fields)),
      createdAt: Value(op.createdAt),
    );

Value<T> _v<T>(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  return Value(f[key] as T);
}

Value<int> _vInt(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  return Value((f[key] as num).toInt());
}

/// 非空文本字段（带默认值的列，例如 `material`）：老 op 里没有这个键时
/// 保留列默认值，不写 null（列是 NOT NULL）。
Value<String> _vString(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  return Value(f[key]?.toString() ?? '');
}

Value<int?> _vIntOrNull(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  final raw = f[key];
  return Value(raw == null ? null : (raw as num).toInt());
}

Value<double> _vDouble(Map<String, dynamic> f, String key) =>
    f.containsKey(key) ? Value((f[key] as num).toDouble()) : Value.absent();

Value<bool> _vBool(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  final v = f[key];
  return Value(v == 1 || v == true);
}

/// `options_json`：op / 字段映射里存 JSON 字符串，companion 要 `List<Option>`。
Value<List<Option>> _vOptions(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  return Value(const OptionsListConverter().fromSql(f[key]?.toString()));
}

/// `choice_json` / `warnings_json`：JSON 字符串 → `List<String>`。
Value<List<String>> _vStrings(Map<String, dynamic> f, String key) {
  if (!f.containsKey(key)) return const Value.absent();
  return Value(const StringListConverter().fromSql(f[key]?.toString()));
}

Map<String, Map<String, dynamic>> _clocksToRaw(
        Map<String, FieldClock> clocks) =>
    clocks.map((k, v) => MapEntry(k, v.toJson()));
