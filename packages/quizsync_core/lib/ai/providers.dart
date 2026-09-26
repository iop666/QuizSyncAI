import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'provider.dart';

/// 一次 AI 请求的完整描述（构造与发送分离：构造可离线单测）。
class AiHttpRequest {
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  const AiHttpRequest({required this.url, required this.headers, required this.body});
}

/// 把 HTTP 响应/异常翻译成 [AiException] 的公共出口。
AiException translateDioError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AiException(AiErrorKind.timeout, '请求超时');
      case DioExceptionType.connectionError:
        return const AiException(AiErrorKind.network, '连接失败');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final msg = e.response?.data?.toString() ?? '';
        if (status == 401 || status == 403) {
          return AiException(AiErrorKind.auth, 'API Key 无效或无权限($status: $msg)',
              statusCode: status);
        }
        if (status == 429) {
          return AiException(AiErrorKind.rateLimited, '触发限流(429)', statusCode: status);
        }
        if (status == 400) {
          return AiException(AiErrorKind.badRequest, '请求格式错误(400: $msg)',
              statusCode: status);
        }
        if (status >= 500) {
          return AiException(AiErrorKind.serverError, '服务端错误($status)',
              statusCode: status);
        }
        return AiException(AiErrorKind.unknown, 'HTTP $status: $msg', statusCode: status);
      case DioExceptionType.cancel:
        return const AiException(AiErrorKind.unknown, '请求已取消');
      default:
        return AiException(AiErrorKind.unknown, e.message ?? '未知网络错误');
    }
  }
  return AiException(AiErrorKind.unknown, e.toString());
}

/// 供三个真实 provider 复用的发送逻辑。
Future<AiRawResponse> sendAiRequest(
  AiHttpRequest request,
  AiConfig config,
  Dio? dio,
) async {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: Duration(seconds: config.timeoutSeconds),
        receiveTimeout: Duration(seconds: config.timeoutSeconds),
        sendTimeout: Duration(seconds: config.timeoutSeconds),
        validateStatus: (s) => s != null && s < 500, // 5xx 也走异常翻译
      ));
  final sw = Stopwatch()..start();
  try {
    // 注意泛型必须是 dynamic 而不是 Map：网关/代理返回 HTML 错误页（502/504）
    // 或 text/plain 时，`post<Map<String, dynamic>>` 会在 Dio 内部抛
    // 「type 'String' is not a subtype of type 'Map<String, dynamic>?'」，
    // 状态码被丢掉，401/5xx 于是被误判成 unknown 且不再重试。
    final resp = await client.post<dynamic>(
      request.url.toString(),
      options: Options(headers: request.headers, validateStatus: (s) => true),
      data: request.body,
    );
    sw.stop();
    final status = resp.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final text = extractContentText(resp.data);
      return AiRawResponse(text: text, latencyMs: sw.elapsedMilliseconds);
    }
    throw _statusError(status, resp.data);
  } on AiException {
    rethrow;
  } catch (e) {
    throw translateDioError(e);
  }
}

AiException _statusError(int status, Object? data) {
  var msg = data?.toString() ?? '';
  if (msg.length > 300) msg = '${msg.substring(0, 300)}…';
  if (status == 401 || status == 403) {
    return AiException(AiErrorKind.auth, 'API Key 无效或无权限($status: $msg)', statusCode: status);
  }
  if (status == 429) {
    return AiException(AiErrorKind.rateLimited, '触发限流(429)', statusCode: status);
  }
  if (status == 400) {
    return AiException(AiErrorKind.badRequest, '请求格式错误(400: $msg)', statusCode: status);
  }
  if (status >= 500) {
    return AiException(AiErrorKind.serverError, '服务端错误($status)', statusCode: status);
  }
  return AiException(AiErrorKind.unknown, 'HTTP $status: $msg', statusCode: status);
}

/// 从各家响应体里抽出文本（choices[0].message.content / content[].text / candidates）。
String extractContentText(Object? raw) {
  final data = raw is Map ? Map<String, dynamic>.from(raw) : null;
  if (data == null) return '';
  // OpenAI 兼容
  final choices = data['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final message = first['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map>()
              .map((p) => p['text']?.toString() ?? '')
              .join();
        }
      }
    }
  }
  // Anthropic
  final content = data['content'];
  if (content is List) {
    final text = content
        .whereType<Map>()
        .where((p) => p['type'] == 'text')
        .map((p) => p['text']?.toString() ?? '')
        .join();
    if (text.isNotEmpty) return text;
  }
  // Gemini
  final candidates = data['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final first = candidates.first;
    if (first is Map) {
      final c = first['content'];
      if (c is Map) {
        final parts = c['parts'];
        if (parts is List) {
          return parts
              .whereType<Map>()
              .map((p) => p['text']?.toString() ?? '')
              .join();
        }
      }
    }
  }
  return '';
}

/// `openai-compatible`（默认）：OpenAI、DashScope 兼容模式（Qwen-VL）、
/// 智谱 GLM-4V、DeepSeek 等一切 OpenAI 兼容端点。
class OpenAiCompatibleProvider extends QuizAiProvider {
  final Dio? dio;
  OpenAiCompatibleProvider({this.dio});

  static const defaultBaseUrl = 'https://api.openai.com/v1';

  @override
  String get id => 'openai-compatible';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) =>
      sendAiRequest(
          buildRequest(
              jpegBytesList: jpegBytesList, prompt: prompt, config: config),
          config,
          dio);

  AiHttpRequest buildRequest({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) {
    final base = config.baseUrl.isEmpty ? defaultBaseUrl : config.baseUrl;
    return AiHttpRequest(
      url: Uri.parse('$base/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
      body: {
        'model': config.model,
        'messages': [
          {
            'role': 'user',
            // 多页：同一条消息里按顺序放多张图（OpenAI 兼容端点支持多个
            // image_url 内容块）。
            'content': [
              {'type': 'text', 'text': prompt},
              for (final bytes in jpegBytesList)
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
                  },
                },
            ],
          },
        ],
      },
    );
  }
}

/// `anthropic`：`POST {baseUrl}/v1/messages`，图片走 image + base64 块。
class AnthropicProvider extends QuizAiProvider {
  final Dio? dio;
  AnthropicProvider({this.dio});

  static const defaultBaseUrl = 'https://api.anthropic.com';

  @override
  String get id => 'anthropic';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) =>
      sendAiRequest(
          buildRequest(
              jpegBytesList: jpegBytesList, prompt: prompt, config: config),
          config,
          dio);

  AiHttpRequest buildRequest({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) {
    final base = config.baseUrl.isEmpty ? defaultBaseUrl : config.baseUrl;
    return AiHttpRequest(
      url: Uri.parse('$base/v1/messages'),
      headers: {
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: {
        'model': config.model,
        'max_tokens': 4096,
        'messages': [
          {
            'role': 'user',
            'content': [
              for (final bytes in jpegBytesList)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/jpeg',
                    'data': base64Encode(bytes),
                  },
                },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
      },
    );
  }
}

/// `gemini`：`POST {baseUrl}/v1beta/models/{model}:generateContent`，图片走 inline_data。
class GeminiProvider extends QuizAiProvider {
  final Dio? dio;
  GeminiProvider({this.dio});

  static const defaultBaseUrl = 'https://generativelanguage.googleapis.com';

  @override
  String get id => 'gemini';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) =>
      sendAiRequest(
          buildRequest(
              jpegBytesList: jpegBytesList, prompt: prompt, config: config),
          config,
          dio);

  AiHttpRequest buildRequest({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) {
    final base = config.baseUrl.isEmpty ? defaultBaseUrl : config.baseUrl;
    return AiHttpRequest(
      url: Uri.parse(
          '$base/v1beta/models/${config.model}:generateContent?key=${config.apiKey}'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: {
        'contents': [
          {
            'parts': [
              for (final bytes in jpegBytesList)
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Encode(bytes),
                  },
                },
              {'text': prompt},
            ],
          },
        ],
      },
    );
  }
}
