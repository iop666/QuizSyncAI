import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

void main() {
  group('matchedOptionLabels（标绿判定核心）', () {
    const options = [
      Option(label: 'A', text: '甲'),
      Option(label: 'B', text: '乙'),
      Option(label: 'C', text: '丙'),
      Option(label: 'D', text: '丁'),
    ];

    test('单选：命中一个 label', () {
      const answer = AnswerValue(choice: ['B']);
      expect(answer.matchedOptionLabels(options), {'B'});
    });

    test('多选：命中多个 label', () {
      const answer = AnswerValue(choice: ['B', 'D']);
      expect(answer.matchedOptionLabels(options), {'B', 'D'});
    });

    test('非法 label 自动剔除', () {
      const answer = AnswerValue(choice: ['B', 'E', 'F']);
      expect(answer.matchedOptionLabels(options), {'B'});
    });

    test('全部非法 → 空集合（不标绿）', () {
      const answer = AnswerValue(choice: ['X', 'Y']);
      expect(answer.matchedOptionLabels(options), isEmpty);
    });

    test('choice 为空 → 空集合', () {
      const answer = AnswerValue(choice: [], text: null);
      expect(answer.matchedOptionLabels(options), isEmpty);
      const noAnswer = AnswerValue();
      expect(noAnswer.matchedOptionLabels(options), isEmpty);
    });

    test('判断题：只有「对」命中', () {
      const judgeOptions = [
        Option(label: '对', text: '对'),
        Option(label: '错', text: '错'),
      ];
      const answer = AnswerValue(choice: ['对']);
      expect(answer.matchedOptionLabels(judgeOptions), {'对'});
    });

    test('重复 label 去重', () {
      const answer = AnswerValue(choice: ['B', 'B']);
      expect(answer.matchedOptionLabels(options), {'B'});
    });
  });
}
