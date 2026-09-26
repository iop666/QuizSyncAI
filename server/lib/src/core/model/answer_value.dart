import 'option.dart';

/// 结构化答案：`answer` 字段的代码化载体。
///
/// 标绿的判定**只**依赖本类（`ai-contract.md` 第 5 节），
/// 严禁从解析文本里搜索答案。
class AnswerValue {
  /// 选项类题目的答案 label 列表；单选恰好 1 个，多选 1 个或多个。
  /// 填空 / 主观题为 null 或空。
  final List<String>? choice;

  /// 填空 / 主观题的答案文本；选项类题目为 null。
  final String? text;

  const AnswerValue({this.choice, this.text});

  bool get isChoiceEmpty => choice == null || choice!.isEmpty;
  bool get isTextEmpty => text == null || text!.isEmpty;
  bool get isEmpty => isChoiceEmpty && isTextEmpty;

  /// 标绿判定核心：`answer.choice` ∩ `options[].label`，非法 label 自动剔除。
  Set<String> matchedOptionLabels(List<Option> options) {
    if (isChoiceEmpty) return const {};
    final labels = options.map((o) => o.label).toSet();
    return choice!.where(labels.contains).toSet();
  }

  Map<String, dynamic> toJson() => {
        'choice': choice == null ? null : List<String>.from(choice!),
        'text': text,
      };

  factory AnswerValue.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AnswerValue();
    final choiceRaw = json['choice'];
    List<String>? choice;
    if (choiceRaw is List) {
      choice = choiceRaw.map((e) => e.toString()).toList();
    }
    return AnswerValue(
      choice: choice,
      text: json['text']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnswerValue &&
      _listEq(other.choice, choice) &&
      other.text == text;

  @override
  int get hashCode => Object.hash(Object.hashAll(choice ?? const []), text);

  @override
  String toString() => 'AnswerValue(choice: $choice, text: $text)';
}

bool _listEq(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
