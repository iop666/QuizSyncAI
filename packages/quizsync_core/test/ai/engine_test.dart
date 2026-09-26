import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

FakeAiProvider fake(String fixture) =>
    FakeAiProvider('test/fixtures/$fixture');

Future<AnalysisOutcome> analyzeWith(
  QuizAiProvider provider, {
  String imageHash = 'fresh-hash',
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = QuizSyncDb(NativeDatabase.memory());
  final repo = CoreRepository(db: db, deviceId: 'dev');
  final engine = AnalysisEngine(
    provider: provider,
    cache: AnalysisCache(repo),
    quota: QuotaGuard(db, dailyLimit: 200),
    deviceId: 'dev',
    retry: const RetryPolicy(sleeper: _noSleep),
  );
  try {
    return await engine.analyzeImage(
      jpegBytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
      imageHash: imageHash,
      config: const AiConfig(model: 'test-model'),
    );
  } finally {
    await db.close();
  }
}

void main() {
  group('AnalysisEngine 端到端（FakeAiProvider + fixture，无网络）', () {
    test('单选题 fixture → 1 题，标绿字段齐全', () async {
      final out = await analyzeWith(fake('single_choice.json'));
      expect(out.errorCode, isNull);
      expect(out.questions.length, 1);
      final q = out.questions.first;
      expect(q.choice, ['B']);
      expect(computeHighlight(q).optionLabels, {'B'});
      expect(out.providerCalls, 1);
    });

    test('multi + judge fixture → 2 题，多题命中与判断命中', () async {
      final out = await analyzeWith(fake('multi_and_judge.json'));
      expect(out.questions.length, 2);
      expect(computeHighlight(out.questions[0]).optionLabels, {'A', 'C', 'D'});
      expect(computeHighlight(out.questions[1]).optionLabels, {'对'});
    });

    test('blank + subjective fixture → 答案文本标绿 + 需复核徽标', () async {
      final out = await analyzeWith(fake('blank_subjective.json'));
      expect(out.questions.length, 2);
      final h0 = computeHighlight(out.questions[0]);
      expect(h0.highlightAnswerText, isTrue);
      final h1 = computeHighlight(out.questions[1]);
      expect(h1.highlightAnswerText, isTrue);
      expect(h1.needsReview, isTrue);
    });

    test('questions 为空 → no_question_found', () async {
      final out = await analyzeWith(fake('no_questions.json'));
      expect(out.errorCode, 'no_question_found');
      expect(out.questions, isEmpty);
    });

    test('非法 JSON 两次 → parseFailed + 保留原文', () async {
      final provider = fake('invalid.txt');
      final out = await analyzeWith(provider);
      expect(out.parseFailed, isTrue);
      expect(out.errorCode, 'ai_bad_response');
      expect(out.rawText, isNotEmpty);
      expect(provider.callCount, 2, reason: '初次 + 严格提醒重试 1 次');
    });

    test('markdown 围栏 fixture → 剥离后正常解析', () async {
      final out = await analyzeWith(fake('markdown_fenced.md'));
      expect(out.errorCode, isNull);
      expect(out.questions.first.choice, ['B']);
    });
  });
}

Future<void> _noSleep(Duration d) async {}
