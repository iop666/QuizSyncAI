import 'dart:typed_data';

import 'package:quizsync_server/quizsync_server_core.dart';
import 'package:quizsync_server/src/engine.dart';
import 'package:test/test.dart';

import 'support.dart';

/// 按顺序返回不同文本的 provider（容错解析第 4 步用）。
class QueueProvider extends QuizAiProvider {
  final List<String> texts;
  int calls = 0;

  QueueProvider(this.texts);

  @override
  String get id => 'queue';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    final text = texts[calls < texts.length ? calls : texts.length - 1];
    calls++;
    return AiRawResponse(text: text, latencyMs: 5);
  }
}

void main() {
  RecognitionEngine engineWith(QuizAiProvider provider) => RecognitionEngine(
        deviceId: 'server-device',
        providerOf: (_) => provider,
      );

  const config = AiConfig(
    providerId: 'openai-compatible',
    baseUrl: 'https://example.invalid',
    apiKey: 'k',
    model: 'm',
  );

  test('正常返回：题目按契约解析出来，sessionId 由调用方回填', () async {
    final provider = ScriptedProvider(kFixtureAiText);
    final outcome = await engineWith(provider).recognize(
      jpegBytesList: [kJpegBytes],
      config: config,
    );
    expect(outcome.ok, isTrue);
    expect(outcome.questions, hasLength(2));
    expect(outcome.questions.first.questionNo, '12');
    expect(outcome.questions.first.choice, ['B']);
    expect(outcome.questions.first.type, QuestionType.single);
    expect(outcome.questions[1].type, QuestionType.subjective);
    expect(outcome.questions[1].answerText, contains('①'));
    expect(provider.lastImageCount, 1);
    expect(outcome.rawText, isNotEmpty);
  });

  test('多页：把全部图片一次性交给 provider', () async {
    final provider = ScriptedProvider(kFixtureAiText);
    await engineWith(provider).recognize(
      jpegBytesList: [
        Uint8List.fromList([1, 2, 1]),
        Uint8List.fromList([1, 2, 2]),
        Uint8List.fromList([1, 2, 3]),
      ],
      config: config,
    );
    expect(provider.lastImageCount, 3);
  });

  test('返回不是 JSON：先严格提醒重试一次，仍不行则保留原文并报 ai_bad_response', () async {
    final provider = QueueProvider(['这不是 JSON', '仍然不是 JSON']);
    final outcome = await engineWith(provider).recognize(
      jpegBytesList: [kJpegBytes],
      config: config,
    );
    expect(provider.calls, 2);
    expect(outcome.ok, isFalse);
    expect(outcome.errorCode, 'ai_bad_response');
    expect(outcome.rawText, '仍然不是 JSON');
  });

  test('第一次不是 JSON、第二次是：按成功处理（容错第 4 步）', () async {
    final provider = QueueProvider(['抱歉，我不会', kFixtureAiText]);
    final outcome =
        await engineWith(provider).recognize(jpegBytesList: [kJpegBytes], config: config);
    expect(provider.calls, 2);
    expect(outcome.ok, isTrue);
    expect(outcome.questions, hasLength(2));
  });

  test('题目为空 → no_question_found（提示用户这张图没题）', () async {
    final outcome = await engineWith(ScriptedProvider('{"questions": []}')).recognize(
      jpegBytesList: [kJpegBytes],
      config: config,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.errorCode, 'no_question_found');
  });

  test('错误码映射与协议一致', () async {
    final cases = {
      AiErrorKind.timeout: 'ai_timeout',
      AiErrorKind.auth: 'ai_auth',
      AiErrorKind.rateLimited: 'ai_rate_limited',
      AiErrorKind.badRequest: 'ai_bad_response',
      AiErrorKind.network: 'internal',
      AiErrorKind.serverError: 'internal',
    };
    for (final entry in cases.entries) {
      final outcome = await engineWith(
        ScriptedProvider('', failure: AiException(entry.key, 'boom')),
      ).recognize(jpegBytesList: [kJpegBytes], config: config);
      expect(outcome.errorCode, entry.value, reason: '${entry.key}');
      expect(outcome.errorMessage, isNotEmpty);
    }
  });

  test('没有图片 → internal，且不调用 provider', () async {
    final provider = ScriptedProvider(kFixtureAiText);
    final outcome =
        await engineWith(provider).recognize(jpegBytesList: [], config: config);
    expect(outcome.errorCode, 'internal');
    expect(provider.calls, 0);
  });

  test('provider 注册表覆盖三家', () {
    expect(RecognitionEngine.createProvider('openai-compatible').id, 'openai-compatible');
    expect(RecognitionEngine.createProvider('anthropic').id, 'anthropic');
    expect(RecognitionEngine.createProvider('gemini').id, 'gemini');
    expect(RecognitionEngine.createProvider('unknown').id, 'openai-compatible');
  });
}
