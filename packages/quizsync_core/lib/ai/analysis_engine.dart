import 'dart:typed_data';

import '../model/question.dart';
import 'analysis_cache.dart';
import 'prompt.dart';
import 'provider.dart';
import 'quota_guard.dart';
import 'response_parser.dart';
import 'retry_policy.dart';

/// 一次分析的最终结论。
/// error_code 取值与 `protocol.md` 3.4 一致：
/// ai_timeout | ai_auth | ai_rate_limited | ai_bad_response |
/// ai_quota_exceeded | no_question_found | internal | null(成功)
class AnalysisOutcome {
  final List<Question> questions;
  final bool fromCache;

  /// 命中缓存时的源会话。
  final String? cacheSessionId;
  final String rawText;

  /// 解析失败时保留的原始返回（供人工查看）。
  final bool parseFailed;
  final int latencyMs;
  final String? errorCode;
  final String? errorMessage;
  final int providerCalls;

  const AnalysisOutcome({
    this.questions = const [],
    this.fromCache = false,
    this.cacheSessionId,
    this.rawText = '',
    this.parseFailed = false,
    this.latencyMs = 0,
    this.errorCode,
    this.errorMessage,
    this.providerCalls = 0,
  });

  bool get ok => errorCode == null;
}

/// 从「一张 JPEG 字节」到「结构化题目列表 + 标绿结论」的完整链路（M2 目标）。
class AnalysisEngine {
  final QuizAiProvider provider;
  final AnalysisCache cache;
  final QuotaGuard quota;
  final RetryPolicy retry;
  final String deviceId;

  AnalysisEngine({
    required this.provider,
    required this.cache,
    required this.quota,
    required this.deviceId,
    RetryPolicy? retry,
  }) : retry = retry ?? const RetryPolicy();

  /// 入口。全程不直接接触 UI / 数据库会话（会话落库由调用方负责）。
  ///
  /// [useCache] 为 false 时跳过缓存回放，强制真实调用 AI（`force_reanalyze`
  /// 与「重新分析」用）。缓存命中的题目带着**原会话**的 questionId，若被写进
  /// 另一个新会话，questionId 冲突会让新会话拿到 0 道题（reviewer 已复现）。
  Future<AnalysisOutcome> analyzeImage({
    required Uint8List jpegBytes,
    required String imageHash,
    required AiConfig config,
    bool useCache = true,
  }) =>
      analyzeImages(
        jpegBytesList: [jpegBytes],
        imageHash: imageHash,
        config: config,
        useCache: useCache,
      );

  /// 多页入口（用户需求 4）：一次请求带 1..6 张图片，AI 按页序合并成题。
  ///
  /// 缓存只对**单图**生效：会话级缓存按 `sessions.image_hash`（= 第一页）
  /// 查找，多页组合无法用它区分「首页相同但后续页不同」的两次识别，
  /// 命中错缓存比不命中更糟，因此多页直接走真实调用。
  Future<AnalysisOutcome> analyzeImages({
    required List<Uint8List> jpegBytesList,
    required String imageHash,
    required AiConfig config,
    bool useCache = true,
  }) async {
    if (jpegBytesList.isEmpty) {
      return const AnalysisOutcome(
        errorCode: 'internal',
        errorMessage: '没有可分析的图片',
      );
    }
    final promptVersion = computePromptVersion();
    final cacheable = useCache && jpegBytesList.length == 1;

    // 1. 缓存命中 → 直接回放，不调用 API，不占配额。
    if (cacheable) {
      final cached = await cache.lookup(
        imageHash: imageHash,
        promptVersion: promptVersion,
        model: config.model,
      );
      if (cached != null) {
        return AnalysisOutcome(
          questions: cached.questions,
          fromCache: true,
          cacheSessionId: cached.sessionId,
        );
      }
    }

    // 2. 每日配额。
    if (!await quota.canCall) {
      return const AnalysisOutcome(
        errorCode: 'ai_quota_exceeded',
        errorMessage: '今日调用已达上限，可在设置中调整',
      );
    }

    // 3. 网络层重试（超时/连接/5xx/429）。
    final sw = Stopwatch()..start();
    var providerCalls = 0;
    String rawText;
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

      // 4. 容错解析（前 3 步）。
      var json = ResponseParser.tryParseJson(rawText);
      if (json == null) {
        // 第 4 步：附加严格提醒重试 1 次（不占网络重试预算）。
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
        // 第 5 步：保留原始返回供人工查看，标记需复核。
        await quota.recordUsage(
          model: config.model,
          promptVersion: promptVersion,
          imageHash: imageHash,
          ok: false,
          errorCode: 'ai_bad_response',
          latencyMs: sw.elapsedMilliseconds,
        );
        return AnalysisOutcome(
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

      await quota.recordUsage(
        model: config.model,
        promptVersion: promptVersion,
        imageHash: imageHash,
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
      );

      if (parsed.questions.isEmpty) {
        return AnalysisOutcome(
          rawText: rawText,
          latencyMs: sw.elapsedMilliseconds,
          errorCode: 'no_question_found',
          errorMessage: '未识别到题目',
          providerCalls: providerCalls,
        );
      }

      return AnalysisOutcome(
        questions: parsed.questions,
        rawText: rawText,
        latencyMs: sw.elapsedMilliseconds,
        providerCalls: providerCalls,
      );
    } on AiException catch (e) {
      sw.stop();
      await quota.recordUsage(
        model: config.model,
        promptVersion: promptVersion,
        imageHash: imageHash,
        ok: false,
        errorCode: _errorCodeFor(e),
        latencyMs: sw.elapsedMilliseconds,
      );
      return AnalysisOutcome(
        latencyMs: sw.elapsedMilliseconds,
        errorCode: _errorCodeFor(e),
        errorMessage: _userMessageFor(e),
        providerCalls: providerCalls,
      );
    }
  }

  static String _errorCodeFor(AiException e) {
    switch (e.kind) {
      case AiErrorKind.timeout:
        return 'ai_timeout';
      case AiErrorKind.auth:
        return 'ai_auth';
      case AiErrorKind.rateLimited:
        return 'ai_rate_limited';
      case AiErrorKind.badRequest:
        return 'ai_bad_response';
      case AiErrorKind.network:
      case AiErrorKind.serverError:
      case AiErrorKind.unknown:
        return 'internal';
    }
  }

  static String _userMessageFor(AiException e) {
    switch (e.kind) {
      case AiErrorKind.timeout:
        return 'AI 请求超时，已按策略重试仍失败';
      case AiErrorKind.auth:
        return 'API Key 无效或无权限';
      case AiErrorKind.rateLimited:
        return '触发限流，稍后重试';
      case AiErrorKind.badRequest:
        return '请求格式错误';
      case AiErrorKind.network:
        return '无法连接 AI 服务';
      case AiErrorKind.serverError:
        return 'AI 服务端错误';
      case AiErrorKind.unknown:
        return '未知错误：${e.message}';
    }
  }
}
