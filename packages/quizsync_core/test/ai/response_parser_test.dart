import 'dart:io';

import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('ResponseParser 5 步容错（ai-contract.md 第 3 节）', () {
    test('第 1 步：纯 JSON 直接解码', () {
      final json = ResponseParser.tryParseJson(fixture('single_choice.json'));
      expect(json, isNotNull);
      expect(json!['questions'], isA<List>());
      final parsed = ResponseParser.toQuestions(json,
          sessionId: 's', deviceId: 'd', now: 1);
      expect(parsed.questions.length, 1);
      expect(parsed.questions.first.choice, ['B']);
      expect(parsed.droppedEmpty, 0);
    });

    test('第 2 步：markdown 代码围栏剥离后解码', () {
      final json = ResponseParser.tryParseJson(fixture('markdown_fenced.md'));
      expect(json, isNotNull);
      final parsed = ResponseParser.toQuestions(json!,
          sessionId: 's', deviceId: 'd', now: 1);
      expect(parsed.questions.first.stem, '水的化学式是');
    });

    test('第 3 步：前后带解释文字 → 截取首尾大括号', () {
      final json = ResponseParser.tryParseJson(fixture('wrapped_json.txt'));
      expect(json, isNotNull);
      final parsed = ResponseParser.toQuestions(json!,
          sessionId: 's', deviceId: 'd', now: 1);
      expect(parsed.questions.first.choice, ['A']);
    });

    test('多题 fixture：multi + judge 各一', () {
      final json = ResponseParser.tryParseJson(fixture('multi_and_judge.json'));
      final parsed = ResponseParser.toQuestions(json!,
          sessionId: 's', deviceId: 'd', now: 1);
      expect(parsed.questions.length, 2);
      expect(parsed.questions[0].type, QuestionType.multi);
      expect(parsed.questions[1].type, QuestionType.judge);
      expect(parsed.questions[0].ordinal, 0);
      expect(parsed.questions[1].ordinal, 1);
    });

    test('第 5 步前置：完全非法文本 → 前 3 步全 null（引擎层负责标记失败）', () {
      expect(ResponseParser.tryParseJson(fixture('invalid.txt')), isNull);
      expect(ResponseParser.tryParseJson(''), isNull);
    });

    test('空 questions 的合法 JSON', () {
      final json = ResponseParser.tryParseJson(fixture('no_questions.json'));
      final parsed = ResponseParser.toQuestions(json!,
          sessionId: 's', deviceId: 'd', now: 1);
      expect(parsed.questions, isEmpty);
    });

    test('空题干条目被丢弃并计数（schema: stem minLength 1）', () {
      const text =
          '{"questions":[{"stem":"","type":"single","answer":{"choice":["A"]},"analysis":"","confidence":0.9},{"stem":"有效题","type":"single","answer":{"choice":["B"]},"analysis":"","confidence":0.9}]}';
      final parsed = ResponseParser.toQuestions(
          ResponseParser.tryParseJson(text)!,
          sessionId: 's',
          deviceId: 'd',
          now: 1);
      expect(parsed.questions.length, 1);
      expect(parsed.droppedEmpty, 1);
      expect(parsed.questions.first.stem, '有效题');
    });
  });

  group('prompt 与版本', () {
    test('prompt 全文关键段落存在（逐字契约）', () {
      expect(kAiPrompt, contains('你是一个专业的解题助手'));
      expect(kAiPrompt, contains('【输出格式】'));
      expect(kAiPrompt, contains('has_answer_in_image'));
      expect(kAiPrompt, contains('解析要在保证正确的前提下尽量简短'));
    });

    test('promptVersion 稳定且为 v1-<hash8>', () {
      final v = computePromptVersion();
      expect(v, matches(RegExp(r'^v1-[0-9a-f]{8}$')));
      expect(computePromptVersion(), v);
    });
  });
}
