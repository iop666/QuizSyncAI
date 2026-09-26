import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

Question parse(Map<String, dynamic> json) => Question.fromAiJson(
      json,
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      deviceId: 'dev',
      now: 1000,
    );

void main() {
  group('Question.fromAiJson 字段规范化（ai-contract.md 第 3 节表格逐行）', () {
    test('缺 question_no → null', () {
      final q = parse({
        'stem': '题干',
        'type': 'single',
        'options': [
          {'label': 'A', 'text': 'a'},
          {'label': 'B', 'text': 'b'},
        ],
        'answer': {
          'choice': ['A'],
          'text': null,
        },
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.questionNo, isNull);
    });

    test('缺 options 且 single → warning「未识别到选项」', () {
      final q = parse({
        'stem': '题干',
        'type': 'single',
        'answer': {
          'choice': ['A'],
        },
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.options, isEmpty);
      expect(q.warnings, contains('未识别到选项'));
      expect(q.matchedLabels, isEmpty);
    });

    test('缺 answer → warning「未识别出答案」+ need_review', () {
      final q = parse({
        'stem': '题干',
        'type': 'single',
        'options': [
          {'label': 'A', 'text': 'a'},
        ],
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.warnings, contains('未识别出答案'));
      expect(q.needReview, isTrue);
      expect(q.choice, isEmpty);
      expect(q.answerText, isNull);
    });

    test('answer.choice 含不存在 label → 剔除，剩空则 warning「答案与选项不匹配」', () {
      final q = parse({
        'stem': '题干',
        'type': 'single',
        'options': [
          {'label': 'A', 'text': 'a'},
          {'label': 'B', 'text': 'b'},
        ],
        'answer': {
          'choice': ['Z'],
        },
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.choice, isEmpty);
      expect(q.warnings, contains('答案与选项不匹配'));
    });

    test('answer.choice 部分非法 → 只保留合法部分', () {
      final q = parse({
        'stem': '题干',
        'type': 'multi',
        'options': [
          {'label': 'A', 'text': 'a'},
          {'label': 'B', 'text': 'b'},
        ],
        'answer': {
          'choice': ['B', 'Z'],
        },
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.choice, ['B']);
      expect(q.warnings, isNot(contains('答案与选项不匹配')));
    });

    test('缺 confidence → 0.5（触发复核徽标）', () {
      final q = parse({
        'stem': '题干',
        'type': 'blank',
        'options': [],
        'answer': {'text': '42'},
        'analysis': '',
      });
      expect(q.confidence, 0.5);
      expect(q.shouldShowReviewBadge, isTrue);
    });

    test('缺 warnings → []', () {
      final q = parse({
        'stem': '题干',
        'type': 'blank',
        'answer': {'text': '42'},
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.warnings, isEmpty);
    });

    test('不认识的 type → subjective + warning', () {
      final q = parse({
        'stem': '题干',
        'type': '排序题',
        'answer': {'text': '随便'},
        'analysis': '',
        'confidence': 0.9,
      });
      expect(q.type, QuestionType.subjective);
      expect(q.warnings.any((w) => w.contains('未知题型')), isTrue);
    });

    test('judge 缺选项 → 自动补「对 / 错」', () {
      final q = parse({
        'stem': '地球是圆的',
        'type': 'judge',
        'answer': {
          'choice': ['对'],
        },
        'analysis': '',
        'confidence': 0.99,
      });
      expect(q.options.length, 2);
      expect(q.options.map((o) => o.label), ['对', '错']);
      expect(q.matchedLabels, {'对'});
      expect(q.warnings, isNot(contains('未识别到选项')));
    });

    test('正常单选题：无 warning，choice 命中', () {
      final q = parse({
        'question_no': '12',
        'stem': '下列哪项正确',
        'type': 'single',
        'options': [
          {'label': 'A', 'text': 'a'},
          {'label': 'B', 'text': 'b'},
        ],
        'answer': {
          'choice': ['B'],
          'text': null,
        },
        'analysis': '因为 B',
        'confidence': 0.95,
        'need_review': false,
        'has_answer_in_image': false,
        'warnings': [],
      });
      expect(q.warnings, isEmpty);
      expect(q.questionNo, '12');
      expect(q.matchedLabels, {'B'});
      expect(q.shouldShowReviewBadge, isFalse);
      expect(q.answerInImage, isFalse);
    });

    test('填空题：answer.text 生效', () {
      final q = parse({
        'stem': '1+1=',
        'type': 'blank',
        'options': [],
        'answer': {'choice': null, 'text': '2'},
        'analysis': '',
        'confidence': 0.99,
      });
      expect(q.answerText, '2');
      expect(q.choice, isEmpty);
      expect(q.shouldShowReviewBadge, isFalse);
    });

    group('阅读材料 material（用户反馈 15）', () {
      test('给了 material → 入库为材料，题干不含材料', () {
        final q = parse({
          'stem': '下列说法正确的是',
          'material': '阅读下面的文字，完成 1-3 题。\n\n材料正文第一段。',
          'type': 'single',
          'options': [
            {'label': 'A', 'text': 'a'},
            {'label': 'B', 'text': 'b'},
          ],
          'answer': {
            'choice': ['A'],
          },
          'analysis': '',
          'confidence': 0.9,
        });
        expect(q.hasMaterial, isTrue);
        expect(q.material, contains('材料正文第一段'));
        expect(q.stem, '下列说法正确的是');
        expect(q.stem.contains('材料正文第一段'), isFalse);
      });

      test('material 为 null / 缺省 / 空白 → 视为没有材料', () {
        for (final raw in [null, '', '   ']) {
          final q = parse({
            'stem': '题干',
            'material': raw,
            'type': 'blank',
            'options': [],
            'answer': {'choice': null, 'text': 'x'},
            'analysis': '',
            'confidence': 0.9,
          });
          expect(q.hasMaterial, isFalse, reason: 'material=$raw');
          expect(q.material, '');
        }
      });

      test('主观题分点答案 → hasStructuredAnswer 为 true；单行答案为 false', () {
        final multi = parse({
          'stem': '简述影响',
          'type': 'subjective',
          'options': [],
          'answer': {'choice': null, 'text': '①气候：全年高温。\n②地形：以平原为主。'},
          'analysis': '',
          'confidence': 0.9,
        });
        expect(multi.hasStructuredAnswer, isTrue);

        final single = parse({
          'stem': '简述影响',
          'type': 'subjective',
          'options': [],
          'answer': {'choice': null, 'text': '气候与地形共同决定。'},
          'analysis': '',
          'confidence': 0.9,
        });
        expect(single.hasStructuredAnswer, isFalse);
      });
    });
  });
}
