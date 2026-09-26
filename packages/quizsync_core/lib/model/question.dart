import 'answer_value.dart';
import 'option.dart';
import 'question_type.dart';

/// 题目。字段与 `data-model.md` 的 `questions` 表一一对应。
class Question {
  final String questionId;
  final String sessionId;
  final int ordinal;

  /// 图中的题号（如 `12`、`(3)`），可空。
  final String? questionNo;
  final String stem;

  /// 阅读材料 / 文章原文（用户反馈 15）：阅读类题目才有。
  /// 空串 = 无材料；端侧在答案上方**默认折叠**显示，点击可展开。
  final String material;

  final QuestionType type;
  final List<Option> options;

  /// `answer.choice`，已剔除不在 options 里的非法 label。
  final List<String> choice;

  /// `answer.text`（填空 / 主观）。
  final String? answerText;
  final String analysis;
  final double confidence;
  final bool needReview;
  final bool answerInImage;

  /// 题目不全（用户需求 2）：题干或选项被截断/缺失，卡片加黄框。
  final bool incomplete;

  /// 答案是 AI 猜测（用户需求 2）：题干在但选项不全时 AI 推断的答案。
  final bool answerGuessed;
  final List<String> warnings;

  /// 字段级 user_edited 标记（`data-model.md` 2.3）。
  final bool answerEdited;
  final bool analysisEdited;

  /// 逐字段写入时钟 `{field: {"l": lamport, "d": deviceId}}`。
  final Map<String, Map<String, dynamic>> fieldClocks;

  final int createdAt;
  final int updatedAt;
  final String updatedBy;
  final int lamport;
  final int? deletedAt;

  const Question({
    required this.questionId,
    required this.sessionId,
    required this.ordinal,
    this.questionNo,
    required this.stem,
    this.material = '',
    required this.type,
    this.options = const [],
    this.choice = const [],
    this.answerText,
    this.analysis = '',
    this.confidence = 0.5,
    this.needReview = false,
    this.answerInImage = false,
    this.incomplete = false,
    this.answerGuessed = false,
    this.warnings = const [],
    this.answerEdited = false,
    this.analysisEdited = false,
    this.fieldClocks = const {},
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    this.lamport = 0,
    this.deletedAt,
  });

  AnswerValue get answer => AnswerValue(choice: choice, text: answerText);

  /// 标绿命中的选项 label 集合（`ai-contract.md` 第 5 节的代码化）。
  Set<String> get matchedLabels => answer.matchedOptionLabels(options);

  /// 是否应显示「建议复核」徽标（`ai-contract.md` 第 6 节）。
  bool get shouldShowReviewBadge => needReview || confidence < 0.6;

  /// 选项类题型但选项不足 2 个 → 判定为「题目不全」（用户需求 2）。
  /// judge 的「对/错」由 fromAiJson 自动补齐，不会误判。
  bool get hasIncompleteOptions =>
      type.requiresOptions && options.length < minOptionsForType;

  /// 选项类题型「完整」所需的最少选项数。
  static int get minOptionsForType => 2;

  /// 题干是否看起来被截断（以省略号/连接符结尾、或短到不可能成题）。
  bool get hasTruncatedStem {
    final s = stem.trim();
    if (s.length < 4) return true;
    return s.endsWith('…') ||
        s.endsWith('...') ||
        s.endsWith('、') ||
        s.endsWith('和') ||
        s.endsWith('与');
  }

  /// 识别到的题号文本（用户需求 3）：`第 12 题`；无题号则 null。
  String? get questionNoLabel {
    final no = questionNo?.trim();
    if (no == null || no.isEmpty) return null;
    return '第 $no 题';
  }

  /// 卡片/导出标题（用户需求 3）：排序序号在前，识别到的题号在后。
  /// 例：`3. 第 12 题`；无题号时为 `3.`。
  String get displayTitle {
    final no = questionNoLabel;
    return no == null ? '${ordinal + 1}.' : '${ordinal + 1}. $no';
  }

  bool get isDeleted => deletedAt != null;

  /// 是否有阅读材料（用户反馈 15）：端侧据此渲染默认折叠的材料面板。
  bool get hasMaterial => material.trim().isNotEmpty;

  /// 主观/填空答案是否已经是结构化多行（用户反馈 15）：AI 被要求分点作答，
  /// 端侧对多行答案按行渲染（保留换行与序号），单行答案保持原样。
  bool get hasStructuredAnswer {
    final text = answerText ?? '';
    if (!text.contains('\n')) return false;
    return text.split('\n').where((l) => l.trim().isNotEmpty).length > 1;
  }

  Question copyWith({
    String? questionId,
    String? sessionId,
    int? ordinal,
    Object? questionNo = _unset,
    String? stem,
    String? material,
    QuestionType? type,
    List<Option>? options,
    List<String>? choice,
    Object? answerText = _unset,
    String? analysis,
    double? confidence,
    bool? needReview,
    bool? answerInImage,
    bool? incomplete,
    bool? answerGuessed,
    List<String>? warnings,
    bool? answerEdited,
    bool? analysisEdited,
    Map<String, Map<String, dynamic>>? fieldClocks,
    int? createdAt,
    int? updatedAt,
    String? updatedBy,
    int? lamport,
    int? deletedAt,
  }) {
    return Question(
      questionId: questionId ?? this.questionId,
      sessionId: sessionId ?? this.sessionId,
      ordinal: ordinal ?? this.ordinal,
      questionNo:
          questionNo == _unset ? this.questionNo : questionNo as String?,
      stem: stem ?? this.stem,
      material: material ?? this.material,
      type: type ?? this.type,
      options: options ?? this.options,
      choice: choice ?? this.choice,
      answerText: answerText == _unset ? this.answerText : answerText as String?,
      analysis: analysis ?? this.analysis,
      confidence: confidence ?? this.confidence,
      needReview: needReview ?? this.needReview,
      answerInImage: answerInImage ?? this.answerInImage,
      incomplete: incomplete ?? this.incomplete,
      answerGuessed: answerGuessed ?? this.answerGuessed,
      warnings: warnings ?? this.warnings,
      answerEdited: answerEdited ?? this.answerEdited,
      analysisEdited: analysisEdited ?? this.analysisEdited,
      fieldClocks: fieldClocks ?? this.fieldClocks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lamport: lamport ?? this.lamport,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  static const _unset = Object();

  /// 协议 / 持久化层的完整序列化（字段与 DB 列名 snake_case 对齐）。
  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        'session_id': sessionId,
        'ordinal': ordinal,
        'question_no': questionNo,
        'stem': stem,
        'material': material,
        'type': type.wire,
        'options_json': options.map((o) => o.toJson()).toList(),
        'choice_json': List<String>.from(choice),
        'answer_text': answerText,
        'analysis': analysis,
        'confidence': confidence,
        'need_review': needReview ? 1 : 0,
        'answer_in_image': answerInImage ? 1 : 0,
        'incomplete': incomplete ? 1 : 0,
        'answer_guessed': answerGuessed ? 1 : 0,
        'warnings_json': List<String>.from(warnings),
        'analysis_edited': analysisEdited ? 1 : 0,
        'answer_edited': answerEdited ? 1 : 0,
        'field_clocks_json': fieldClocks,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'lamport': lamport,
        'deleted_at': deletedAt,
      };

  /// 与 [toJson] 对应的宽容反序列化（缺字段补默认值）。
  factory Question.fromJson(Map<String, dynamic> json) {
    final optionsRaw = json['options_json'];
    final choiceRaw = json['choice_json'];
    final warningsRaw = json['warnings_json'];
    return Question(
      questionId: json['question_id'].toString(),
      sessionId: json['session_id'].toString(),
      ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
      questionNo: json['question_no']?.toString(),
      stem: json['stem']?.toString() ?? '',
      material: json['material']?.toString() ?? '',
      type: QuestionType.parse(json['type']?.toString()),
      options: optionsRaw is List
          ? optionsRaw
              .whereType<Map>()
              .map((o) => Option.fromJson(Map<String, dynamic>.from(o)))
              .toList()
          : const [],
      choice: choiceRaw is List ? choiceRaw.map((e) => e.toString()).toList() : const [],
      answerText: json['answer_text']?.toString(),
      analysis: json['analysis']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      needReview: json['need_review'] == 1 || json['need_review'] == true,
      answerInImage:
          json['answer_in_image'] == 1 || json['answer_in_image'] == true,
      incomplete: json['incomplete'] == 1 || json['incomplete'] == true,
      answerGuessed:
          json['answer_guessed'] == 1 || json['answer_guessed'] == true,
      warnings: warningsRaw is List
          ? warningsRaw.map((e) => e.toString()).toList()
          : const [],
      analysisEdited:
          json['analysis_edited'] == 1 || json['analysis_edited'] == true,
      answerEdited: json['answer_edited'] == 1 || json['answer_edited'] == true,
      fieldClocks: _parseClocks(json['field_clocks_json']),
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      updatedBy: json['updated_by']?.toString() ?? '',
      lamport: (json['lamport'] as num?)?.toInt() ?? 0,
      deletedAt: (json['deleted_at'] as num?)?.toInt(),
    );
  }

  /// AI 输出的字段级规范化（`ai-contract.md` 第 3 节表格逐行实现）：
  /// 缺字段补默认值；非法值剔除并追加 warning；不抛异常。
  factory Question.fromAiJson(
    Map<String, dynamic> json, {
    required String questionId,
    required String sessionId,
    required int ordinal,
    required String deviceId,
    required int now,
  }) {
    final warnings = <String>[];
    final rawWarnings = json['warnings'];
    if (rawWarnings is List) {
      warnings.addAll(rawWarnings.map((e) => e.toString()));
    }

    final typeRaw = json['type']?.toString();
    if (!QuestionType.isKnown(typeRaw)) {
      warnings.add('未知题型 ${typeRaw ?? '(null)'}，按 subjective 处理');
    }
    final type = QuestionType.parse(typeRaw);

    var options = <Option>[];
    final optionsRaw = json['options'];
    if (optionsRaw is List) {
      options = optionsRaw
          .whereType<Map>()
          .map((o) => Option.fromJson(Map<String, dynamic>.from(o)))
          .where((o) => o.label.isNotEmpty)
          .toList();
    }
    if (type == QuestionType.judge && options.isEmpty) {
      // judge 且选项缺失：自动补「对 / 错」。
      options = const [
        Option(label: '对', text: '对'),
        Option(label: '错', text: '错'),
      ];
    }
    if (type.requiresOptions && options.isEmpty) {
      warnings.add('未识别到选项');
    }

    var answer = const AnswerValue();
    final answerRaw = json['answer'];
    if (answerRaw is Map) {
      answer = AnswerValue.fromJson(Map<String, dynamic>.from(answerRaw));
    }

    var choice = answer.choice ?? const <String>[];
    if (choice.isNotEmpty) {
      final labels = options.map((o) => o.label).toSet();
      final valid = choice.where(labels.contains).toList();
      if (valid.length != choice.length) {
        if (valid.isEmpty) {
          warnings.add('答案与选项不匹配');
        }
        choice = valid;
      }
    }

    final answerText = answer.isTextEmpty ? null : answer.text;
    var needReview = json['need_review'] == true;
    if (answer.isEmpty) {
      warnings.add('未识别出答案');
      needReview = true;
    }

    // 用户需求 2：不完整的题目要给用户明确的可见标记，且答案为推断时要注明。
    // ① 单选题/多选题选项少于 2 项（被截断）→ incomplete；
    // ② 已有答案但不完整 → 该答案视为 AI 猜测（answer_guessed）；
    // ③ AI 显式声明 incomplete / answer_is_guess 时同样尊重。
    final lacksOptions = type.requiresOptions && options.length < 2;
    final incomplete = json['incomplete'] == true || lacksOptions;
    final guessed = json['answer_is_guess'] == true ||
        (incomplete && !answer.isEmpty);
    if (lacksOptions && options.isNotEmpty) {
      warnings.add('选项不全（仅 ${options.length} 项）');
    }
    if (incomplete) {
      warnings.add('题目不全，已在卡片上标黄');
    }
    if (guessed) {
      warnings.add('答案为 AI 按题意推断，仅供参考');
      needReview = true;
    }

    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.5;

    // 阅读材料（用户反馈 15）：只有阅读类题目才给；空串/缺省都当没有材料。
    final material = (json['material']?.toString() ?? '').trim();

    return Question(
      questionId: questionId,
      sessionId: sessionId,
      ordinal: ordinal,
      questionNo: json['question_no']?.toString(),
      stem: json['stem']?.toString() ?? '',
      material: material,
      type: type,
      options: options,
      choice: choice,
      answerText: answerText,
      analysis: json['analysis']?.toString() ?? '',
      confidence: confidence,
      needReview: needReview,
      answerInImage: json['has_answer_in_image'] == true,
      incomplete: incomplete,
      answerGuessed: guessed,
      warnings: warnings,
      createdAt: now,
      updatedAt: now,
      updatedBy: deviceId,
    );
  }

  static Map<String, Map<String, dynamic>> _parseClocks(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) =>
          MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    }
    return const {};
  }

  @override
  String toString() =>
      'Question($questionId #$ordinal type=$type stem=${stem.length}ch)';
}
