import 'dart:typed_data';

import '../quizsync_server_core.dart';

/// 一次识别的最终结论。error_code 取值与 `protocol.md` 3.4 逐字一致：
/// `ai_timeout | ai_auth | ai_rate_limited | ai_bad_response | no_question_found | internal`。
class RecognitionOutcome {
  final List<Question> questions;
  final String rawText;
  final bool parseFailed;
  final int latencyMs;
  final String? errorCode;
  final String? errorMessage;
  final int providerCalls;

  const RecognitionOutcome({
    this.questions = const [],
    this.rawText = '',
    this.parseFailed = false,
    this.latencyMs = 0,
    this.errorCode,
    this.errorMessage,
    this.providerCalls = 0,
  });

  bool get ok => errorCode == null;
}

/// 「JPEG 字节 → 结构化题目」的最小识别引擎。
///
/// 与主项目 `packages/quizsync_core/lib/ai/analysis_engine.dart` 的**同一套
/// 流程与同一套错误码**（prompt → 网络重试 → 容错解析 → 严格提醒重试一次），
/// 只去掉 Server 用不到的两块：
///   - 缓存（`AnalysisCache`）：需要数据库，Server 不用数据库；
///   - 每日配额（`QuotaGuard`）：那是 Desktop 设置页里的功能，Server 功能冻结。
///
/// prompt 全文与 JSON 解析规则**没有改动**：Android 拿到的题目结构与连着
/// Desktop 时完全一致。
class RecognitionEngine {
  final String deviceId;

  /// provider 工厂（测试注入假 provider）。
  final QuizAiProvider Function(String providerId) providerOf;

  final RetryPolicy retry;

  RecognitionEngine({
    required this.deviceId,
    QuizAiProvider Function(String providerId)? providerOf,
    RetryPolicy? retry,
  })  : providerOf = providerOf ?? createProvider,
        retry = retry ?? const RetryPolicy();

  Future<RecognitionOutcome> recognize({
    required List<Uint8List> jpegBytesList,
    required AiConfig config,
  }) async {
    if (jpegBytesList.isEmpty) {
      return const RecognitionOutcome(
        errorCode: 'internal',
        errorMessage: '没有可分析的图片',
      );
    }
    final provider = providerOf(config.providerId);
    final sw = Stopwatch()..start();
    var providerCalls = 0;
    var rawText = '';

    try {
      final resp = await withRetry(
        retry,
        () async {
          providerCalls++;
          return provider.analyze(
            jpegBytesList: jpegBytesList,
            prompt: kAiPrompt,
            config: config,
          );
        },
      );
      rawText = resp.text;

      var json = ResponseParser.tryParseJson(rawText);
      if (json == null) {
        // 容错解析第 4 步：附加严格提醒重试 1 次（不占网络重试预算）。
        providerCalls++;
        final stricter = await provider.analyze(
          jpegBytesList: jpegBytesList,
          prompt: '$kAiPrompt\n\n$kStrictJsonReminder',
          config: config,
        );
        rawText = stricter.text;
        json = ResponseParser.tryParseJson(rawText);
      }

      sw.stop();
      if (json == null) {
        // 第 5 步：保留原始返回，标记失败（调用方把它写进会话供「重试」）。
        return RecognitionOutcome(
          rawText: rawText,
          parseFailed: true,
          latencyMs: sw.elapsedMilliseconds,
          errorCode: 'ai_bad_response',
          errorMessage: 'AI 返回无法解析为 JSON，已保留原文',
          providerCalls: providerCalls,
        );
      }

      final parsed = ResponseParser.toQuestions(
        json,
        sessionId: 'pending',
        deviceId: deviceId,
      );
      if (parsed.questions.isEmpty) {
        return RecognitionOutcome(
          rawText: rawText,
          latencyMs: sw.elapsedMilliseconds,
          errorCode: 'no_question_found',
          errorMessage: '未识别到题目',
          providerCalls: providerCalls,
        );
      }
      return RecognitionOutcome(
        questions: parsed.questions,
        rawText: rawText,
        latencyMs: sw.elapsedMilliseconds,
        providerCalls: providerCalls,
      );
    } on AiException catch (e) {
      sw.stop();
      return RecognitionOutcome(
        rawText: rawText,
        latencyMs: sw.elapsedMilliseconds,
        errorCode: errorCodeFor(e),
        errorMessage: userMessageFor(e),
        providerCalls: providerCalls,
      );
    }
  }

  /// 三家 provider 的注册表（与主项目 `apps/desktop` 里注册的是同一批）。
  static QuizAiProvider createProvider(String providerId) => switch (providerId) {
        'anthropic' => AnthropicProvider(),
        'gemini' => GeminiProvider(),
        _ => OpenAiCompatibleProvider(),
      };

  static String errorCodeFor(AiException e) => switch (e.kind) {
        AiErrorKind.timeout => 'ai_timeout',
        AiErrorKind.auth => 'ai_auth',
        AiErrorKind.rateLimited => 'ai_rate_limited',
        AiErrorKind.badRequest => 'ai_bad_response',
        AiErrorKind.network ||
        AiErrorKind.serverError ||
        AiErrorKind.unknown =>
          'internal',
      };

  static String userMessageFor(AiException e) => switch (e.kind) {
        AiErrorKind.timeout => 'AI 请求超时，已按策略重试仍失败',
        AiErrorKind.auth => 'API Key 无效或无权限',
        AiErrorKind.rateLimited => '触发限流，稍后重试',
        AiErrorKind.badRequest => '请求格式错误',
        AiErrorKind.network => '无法连接 AI 服务',
        AiErrorKind.serverError => 'AI 服务端错误',
        AiErrorKind.unknown => '未知错误：${e.message}',
      };
}

/// 「配置齐了没有」的唯一判定（`/info` 的 ai_configured 与流水线的
/// 「主机尚未配置 AI」都用它，避免两处判定漂移）。
extension AiConfigReadiness on AiConfig {
  bool get configured =>
      apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
}

/// 配置 → [AiConfig]（apiKey 只在这里出现，绝不写日志 / 不进状态文件）。
AiConfig aiConfigOf({
  required String providerId,
  required String baseUrl,
  required String apiKey,
  required String model,
}) =>
    AiConfig(
      providerId: providerId,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
