import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

Question q({
  required QuestionType type,
  List<Option> options = const [],
  List<String> choice = const [],
  String? answerText,
  double confidence = 0.9,
  bool needReview = false,
}) =>
    Question(
      questionId: 'q',
      sessionId: 's',
      ordinal: 0,
      stem: 'stem',
      type: type,
      options: options,
      choice: choice,
      answerText: answerText,
      confidence: confidence,
      needReview: needReview,
      createdAt: 1,
      updatedAt: 1,
      updatedBy: 'd',
    );

const abcd = [
  Option(label: 'A', text: 'a'),
  Option(label: 'B', text: 'b'),
  Option(label: 'C', text: 'c'),
  Option(label: 'D', text: 'd'),
];

void main() {
  group('标绿映射（ai-contract.md 第 5 节，7 用例）', () {
    test('1. 单选：只有 B 标绿', () {
      final h = computeHighlight(
          q(type: QuestionType.single, options: abcd, choice: ['B']));
      expect(h.optionLabels, {'B'});
      expect(h.highlightAnswerText, isFalse);
      expect(h.noAnswer, isFalse);
      expect(h.needsReview, isFalse);
    });

    test('2. 多选：B、D 都标绿', () {
      final h = computeHighlight(
          q(type: QuestionType.multi, options: abcd, choice: ['B', 'D']));
      expect(h.optionLabels, {'B', 'D'});
    });

    test('3. 判断：只有「对」标绿', () {
      const judge = [Option(label: '对', text: '对'), Option(label: '错', text: '错')];
      final h = computeHighlight(
          q(type: QuestionType.judge, options: judge, choice: ['对']));
      expect(h.isJudge, isTrue);
      expect(h.optionLabels, {'对'});
    });

    test('4. 填空：answer.text 绿色显示', () {
      final h = computeHighlight(
          q(type: QuestionType.blank, answerText: '42'));
      expect(h.highlightAnswerText, isTrue);
      expect(h.optionLabels, isEmpty);
    });

    test('5. 主观：answer.text 绿色显示', () {
      final h = computeHighlight(
          q(type: QuestionType.subjective, answerText: '光的折射定律是……'));
      expect(h.highlightAnswerText, isTrue);
    });

    test('6. 答案与选项不匹配：不标绿，noAnswer', () {
      final h = computeHighlight(
          q(type: QuestionType.single, options: abcd, choice: ['Z']));
      expect(h.optionLabels, isEmpty);
      expect(h.noAnswer, isTrue);
      expect(h.needsReview, isTrue);
    });

    test('7. answer 为空：不标绿，noAnswer，需复核', () {
      final h = computeHighlight(q(type: QuestionType.single, options: abcd));
      expect(h.hasAnyHighlight, isFalse);
      expect(h.noAnswer, isTrue);
      expect(h.needsReview, isTrue);
    });
  });

  group('置信度徽标（ai-contract.md 第 6 节）', () {
    test('confidence 0.4 → 建议复核徽标', () {
      final h = computeHighlight(
          q(type: QuestionType.single, options: abcd, choice: ['A'], confidence: 0.4));
      expect(h.needsReview, isTrue);
    });

    test('confidence 0.85 → 无徽标', () {
      final h = computeHighlight(
          q(type: QuestionType.single, options: abcd, choice: ['A'], confidence: 0.85));
      expect(h.needsReview, isFalse);
    });

    test('need_review=true 时无论 confidence 都有徽标', () {
      final h = computeHighlight(
          q(type: QuestionType.single, options: abcd, choice: ['A'],
            confidence: 0.95, needReview: true));
      expect(h.needsReview, isTrue);
    });
  });
}
