import 'dart:typed_data';

/// AI 调用配置（`ai-contract.md` 第 1 节）。
class AiConfig {
  /// 'openai-compatible' | 'anthropic' | 'gemini'
  final String providerId;

  /// 可空，空则用 provider 默认。
  final String baseUrl;
  final String apiKey;

  /// 例如 gpt-4o-mini / qwen-vl-max / glm-4v-plus / claude-sonnet / gemini-2.x
  final String model;
  final int timeoutSeconds;
  final int maxRetries;

  const AiConfig({
    this.providerId = 'openai-compatible',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.timeoutSeconds = 90,
    this.maxRetries = 2,
  });

  AiConfig copyWith({
    String? providerId,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? timeoutSeconds,
    int? maxRetries,
  }) =>
      AiConfig(
        providerId: providerId ?? this.providerId,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        maxRetries: maxRetries ?? this.maxRetries,
      );

  Map<String, dynamic> toSecureJson() => {
        'provider_id': providerId,
        'base_url': baseUrl,
        'model': model,
        'timeout_seconds': timeoutSeconds,
        'max_retries': maxRetries,
        // apiKey 绝不出现在 JSON / 日志 / 数据库里。
      };
}

/// provider 的原始返回（只做「发请求取文本」，JSON 解析在 ResponseParser）。
class AiRawResponse {
  final String text;
  final int latencyMs;

  const AiRawResponse({required this.text, required this.latencyMs});
}

/// AI 调用异常分类（重试策略的依据，`ai-contract.md` 第 4 节）。
enum AiErrorKind {
  /// 超时（可重试）
  timeout,

  /// 连接失败（可重试）
  network,

  /// HTTP 5xx（可重试）
  serverError,

  /// HTTP 429（可重试）
  rateLimited,

  /// HTTP 400：请求格式错（不可重试）
  badRequest,

  /// HTTP 401 / 403：Key 无效或无权限（不可重试）
  auth,

  /// 其他未知错误
  unknown,
}

class AiException implements Exception {
  final AiErrorKind kind;
  final int? statusCode;
  final String message;

  const AiException(this.kind, this.message, {this.statusCode});

  bool get retryable =>
      kind == AiErrorKind.timeout ||
      kind == AiErrorKind.network ||
      kind == AiErrorKind.serverError ||
      kind == AiErrorKind.rateLimited;

  @override
  String toString() => 'AiException(${kind.name} $statusCode: $message)';
}

/// Provider 抽象（`ai-contract.md` 第 1 节）。
/// 实现必须可被替换为假实现供单测与回环测试使用。
///
/// 用户需求 4：一次识别可以是多页图片，因此入口是**列表**。
/// 单图调用方（剪贴板、拖入、安卓单击）传长度为 1 的列表即可。
abstract class QuizAiProvider {
  String get id;

  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  });
}

/// 单图便捷调用（内部走多图通道）。
extension QuizAiProviderSingle on QuizAiProvider {
  Future<AiRawResponse> analyzeOne({
    required Uint8List jpegBytes,
    required String prompt,
    required AiConfig config,
  }) =>
      analyze(jpegBytesList: [jpegBytes], prompt: prompt, config: config);
}
