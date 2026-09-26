import 'task_state.dart';

/// 会话 = 一次识别 = 一条历史记录。字段与 `data-model.md` sessions 表一致。
class Session {
  final String sessionId;

  /// 发起端生成的幂等 id。
  final String? taskId;

  /// 所属合集（用户需求 8）。旧数据为 null → 显示「未分类」。
  final String? collectionId;
  final String imageHash;
  final String sourceDevice;
  final TaskState status;
  final String? errorCode;
  final String? errorMessage;
  final String? aiProvider;
  final String? aiModel;
  final String? promptVersion;

  /// 解析失败时保留 AI 原始返回。
  final String? rawResponse;

  /// 命中缓存回放时为 true（`ai-contract.md` 第 4 节）。
  final bool cached;
  final int questionCount;
  final int? latencyMs;

  final Map<String, Map<String, dynamic>> fieldClocks;
  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final int? deletedAt;

  const Session({
    required this.sessionId,
    this.taskId,
    this.collectionId,
    required this.imageHash,
    required this.sourceDevice,
    this.status = TaskState.queued,
    this.errorCode,
    this.errorMessage,
    this.aiProvider,
    this.aiModel,
    this.promptVersion,
    this.rawResponse,
    this.cached = false,
    this.questionCount = 0,
    this.latencyMs,
    this.fieldClocks = const {},
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    this.lamport = 0,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  static const _unset = Object();

  Session copyWith({
    String? taskId,
    Object? collectionId = _unset,
    TaskState? status,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    String? aiProvider,
    String? aiModel,
    String? promptVersion,
    Object? rawResponse = _unset,
    bool? cached,
    int? questionCount,
    Object? latencyMs = _unset,
    Map<String, Map<String, dynamic>>? fieldClocks,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    int? deletedAt,
  }) {
    return Session(
      sessionId: sessionId,
      taskId: taskId ?? this.taskId,
      collectionId: collectionId == _unset
          ? this.collectionId
          : collectionId as String?,
      imageHash: imageHash,
      sourceDevice: sourceDevice,
      status: status ?? this.status,
      errorCode:
          errorCode == _unset ? this.errorCode : errorCode as String?,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      promptVersion: promptVersion ?? this.promptVersion,
      rawResponse: rawResponse == _unset
          ? this.rawResponse
          : rawResponse as String?,
      cached: cached ?? this.cached,
      questionCount: questionCount ?? this.questionCount,
      latencyMs:
          latencyMs == _unset ? this.latencyMs : latencyMs as int?,
      fieldClocks: fieldClocks ?? this.fieldClocks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'task_id': taskId,
        'collection_id': collectionId,
        'image_hash': imageHash,
        'source_device': sourceDevice,
        'status': status.wire,
        'error_code': errorCode,
        'error_message': errorMessage,
        'ai_provider': aiProvider,
        'ai_model': aiModel,
        'prompt_version': promptVersion,
        'raw_response': rawResponse,
        'cached': cached ? 1 : 0,
        'question_count': questionCount,
        'latency_ms': latencyMs,
        'field_clocks_json': fieldClocks,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'lamport': lamport,
        'deleted_at': deletedAt,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        sessionId: json['session_id'].toString(),
        taskId: json['task_id']?.toString(),
        collectionId: json['collection_id']?.toString(),
        imageHash: json['image_hash']?.toString() ?? '',
        sourceDevice: json['source_device']?.toString() ?? '',
        status: TaskState.parse(json['status']?.toString()),
        errorCode: json['error_code']?.toString(),
        errorMessage: json['error_message']?.toString(),
        aiProvider: json['ai_provider']?.toString(),
        aiModel: json['ai_model']?.toString(),
        promptVersion: json['prompt_version']?.toString(),
        rawResponse: json['raw_response']?.toString(),
        cached: json['cached'] == 1 || json['cached'] == true,
        questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
        latencyMs: (json['latency_ms'] as num?)?.toInt(),
        fieldClocks: _parseClocks(json['field_clocks_json']),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
        updatedBy: json['updated_by']?.toString() ?? '',
        lamport: (json['lamport'] as num?)?.toInt() ?? 0,
        deletedAt: (json['deleted_at'] as num?)?.toInt(),
      );

  static Map<String, Map<String, dynamic>> _parseClocks(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) =>
          MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    }
    return const {};
  }

  @override
  String toString() =>
      'Session($sessionId status=$status q=$questionCount @$createdAt)';
}
