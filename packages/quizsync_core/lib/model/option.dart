/// 题目选项。label 如 `A` / `对`，text 为选项内容。
class Option {
  final String label;
  final String text;

  const Option({required this.label, required this.text});

  Map<String, dynamic> toJson() => {'label': label, 'text': text};

  factory Option.fromJson(Map<String, dynamic> json) => Option(
        label: (json['label'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) =>
      other is Option && other.label == label && other.text == text;

  @override
  int get hashCode => Object.hash(label, text);

  @override
  String toString() => 'Option($label: $text)';
}
