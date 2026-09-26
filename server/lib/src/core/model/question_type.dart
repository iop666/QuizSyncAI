/// 题型。取值与 `ai-contract.md` 第 3 节 enum 逐字一致。
enum QuestionType {
  single('single'),
  multi('multi'),
  judge('judge'),
  blank('blank'),
  subjective('subjective');

  final String wire;
  const QuestionType(this.wire);

  /// 不认识的 type 按 subjective 处理（是否记 warning 由调用方决定）。
  static QuestionType parse(String? raw) =>
      QuestionType.values.firstWhere(
        (t) => t.wire == raw,
        orElse: () => QuestionType.subjective,
      );

  static bool isKnown(String? raw) =>
      QuestionType.values.any((t) => t.wire == raw);

  /// 该题型必须有选项（单选 / 多选 / 判断）。
  bool get requiresOptions =>
      this == QuestionType.single ||
      this == QuestionType.multi ||
      this == QuestionType.judge;

  @override
  String toString() => wire;
}
