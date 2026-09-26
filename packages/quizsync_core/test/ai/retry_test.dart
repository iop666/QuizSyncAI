import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 按脚本回放结果的 provider：AiException 或 AiRawResponse 依次返回。
class ScriptedProvider extends QuizAiProvider {
  final List<Object> script;
  final List<String> receivedPrompts = [];
  int callCount = 0;

  ScriptedProvider(this.script);

  @override
  String get id => 'scripted';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    receivedPrompts.add(prompt);
    final item = script[callCount.clamp(0, script.length - 1)];
    callCount++;
    if (item is AiException) throw item;
    return item as AiRawResponse;
  }
}

const okJson =
    AiRawResponse(text: '{"questions":[{"stem":"1+1=","type":"blank","answer":{"text":"2"},"analysis":"","confidence":0.9}]}', latencyMs: 10);

Future<(AnalysisOutcome, ScriptedProvider, List<Duration>)> run(
    List<Object> script) async {
  final provider = ScriptedProvider(script);
  final waits = <Duration>[];
  final db = await _mkDb();
  final repo = CoreRepository(db: db, deviceId: 'dev');
  final engine = AnalysisEngine(
    provider: provider,
    cache: AnalysisCache(repo),
    quota: QuotaGuard(db, dailyLimit: 200),
    deviceId: 'dev',
    retry: RetryPolicy(sleeper: (d) async => waits.add(d)),
  );
  final outcome = await engine.analyzeImage(
    jpegBytes: Uint8List.fromList([1, 2, 3]),
    imageHash: 'hash-${provider.hashCode}',
    config: const AiConfig(model: 'test-model'),
  );
  await db.close();
  return (outcome, provider, waits);
}

Future<QuizSyncDb> _mkDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return Future.value(QuizSyncDb(NativeDatabase.memory()));
}

void main() {
  group('网络层重试（ai-contract.md 第 4 节）', () {
    test('超时 → 超时 → 成功：总共调用 3 次，退避 1s、3s', () async {
      final (outcome, provider, waits) = await run([
        const AiException(AiErrorKind.timeout, '超时1'),
        const AiException(AiErrorKind.timeout, '超时2'),
        okJson,
      ]);
      expect(provider.callCount, 3);
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 3)]);
      expect(outcome.errorCode, isNull);
      expect(outcome.questions.first.answerText, '2');
    });

    test('401：只调用 1 次，不重试，错误码 ai_auth', () async {
      final (outcome, provider, waits) = await run([
        const AiException(AiErrorKind.auth, 'Key 无效', statusCode: 401),
      ]);
      expect(provider.callCount, 1);
      expect(waits, isEmpty);
      expect(outcome.errorCode, 'ai_auth');
      expect(outcome.errorMessage, contains('API Key'));
    });

    test('403 同样不重试', () async {
      final (outcome, provider, _) = await run([
        const AiException(AiErrorKind.auth, '无权限', statusCode: 403),
      ]);
      expect(provider.callCount, 1);
      expect(outcome.errorCode, 'ai_auth');
    });

    test('429：按退避重试，重试成功则不报错', () async {
      final (outcome, provider, waits) = await run([
        const AiException(AiErrorKind.rateLimited, '限流', statusCode: 429),
        okJson,
      ]);
      expect(provider.callCount, 2);
      expect(waits, [const Duration(seconds: 1)]);
      expect(outcome.errorCode, isNull);
    });

    test('重试预算耗尽 → ai_timeout', () async {
      final (outcome, provider, waits) = await run([
        const AiException(AiErrorKind.timeout, '超时'),
        const AiException(AiErrorKind.timeout, '超时'),
        const AiException(AiErrorKind.timeout, '超时'),
      ]);
      expect(provider.callCount, 3, reason: '默认 maxRetries=2 → 1+2=3 次');
      expect(waits.length, 2);
      expect(outcome.errorCode, 'ai_timeout');
    });

    test('400：不重试，错误码 ai_bad_response', () async {
      final (outcome, provider, _) = await run([
        const AiException(AiErrorKind.badRequest, '请求格式错误', statusCode: 400),
      ]);
      expect(provider.callCount, 1);
      expect(outcome.errorCode, 'ai_bad_response');
    });
  });

  group('JSON 解析失败的额外重试（不占网络重试预算）', () {
    test('第 1 次返回非法 JSON → 附加严格提醒重试 1 次成功', () async {
      final (outcome, provider, waits) = await run([
        const AiRawResponse(text: '抱歉，这不是 JSON', latencyMs: 5),
        okJson,
      ]);
      expect(provider.callCount, 2);
      expect(waits, isEmpty, reason: '解析重试不占网络退避预算');
      expect(provider.receivedPrompts[1], contains(kStrictJsonReminder));
      expect(outcome.errorCode, isNull);
      expect(outcome.questions.length, 1);
    });

    test('两次都非法 JSON → parseFailed + 保留原文 + ai_bad_response', () async {
      final (outcome, provider, _) = await run([
        const AiRawResponse(text: '第一次垃圾 {{{', latencyMs: 5),
        const AiRawResponse(text: '第二次还是垃圾', latencyMs: 5),
      ]);
      expect(provider.callCount, 2);
      expect(outcome.parseFailed, isTrue);
      expect(outcome.errorCode, 'ai_bad_response');
      expect(outcome.rawText, '第二次还是垃圾', reason: '保留最后一次原始返回');
    });
  });
}
