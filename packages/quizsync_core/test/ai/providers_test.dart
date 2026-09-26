import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

void main() {
  final bytes = Uint8List.fromList(List.filled(4, 7));
  const config = AiConfig(
    providerId: 'openai-compatible',
    apiKey: 'sk-test',
    model: 'gpt-4o-mini',
  );

  group('openai-compatible 请求构造', () {
    test('默认 baseUrl 与鉴权头', () {
      final req = OpenAiCompatibleProvider()
          .buildRequest(jpegBytesList: [bytes], prompt: 'p', config: config);
      expect(req.url.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(req.headers['Authorization'], 'Bearer sk-test');
      final body = req.body;
      expect(body['model'], 'gpt-4o-mini');
      final messages = body['messages'] as List;
      final content = (messages.first as Map)['content'] as List;
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      final url = (content[1] as Map)['image_url'] as Map;
      expect(url['url'],
          startsWith('data:image/jpeg;base64,${base64Encode(bytes).substring(0, 8)}'));
    });

    test('自定义 baseUrl（DashScope 兼容模式等）', () {
      final req = OpenAiCompatibleProvider().buildRequest(
        jpegBytesList: [bytes],
        prompt: 'p',
        config: config.copyWith(
            baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
      );
      expect(req.url.toString(),
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions');
    });
  });

  group('anthropic 请求构造', () {
    test('路径 /v1/messages、x-api-key、image base64 块', () {
      final req = AnthropicProvider().buildRequest(
          jpegBytesList: [bytes], prompt: 'p', config: config);
      expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'sk-test');
      expect(req.headers['anthropic-version'], '2023-06-01');
      final messages = req.body['messages'] as List;
      final content = (messages.first as Map)['content'] as List;
      expect(content[0]['type'], 'image');
      expect((content[0] as Map)['source'], {
        'type': 'base64',
        'media_type': 'image/jpeg',
        'data': base64Encode(bytes),
      });
      expect(content[1], {'type': 'text', 'text': 'p'});
      expect(req.body['max_tokens'], greaterThan(0));
    });
  });

  group('gemini 请求构造', () {
    test('路径含 model 与 key、inline_data', () {
      final req = GeminiProvider().buildRequest(
          jpegBytesList: [bytes], prompt: 'p', config: config);
      expect(
        req.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gpt-4o-mini:generateContent?key=sk-test',
      );
      final contents = req.body['contents'] as List;
      final parts = (contents.first as Map)['parts'] as List;
      expect((parts[0] as Map)['inline_data'], {
        'mime_type': 'image/jpeg',
        'data': base64Encode(bytes),
      });
      expect(parts[1], {'text': 'p'});
    });
  });

  group('多页请求构造（用户需求 4）', () {
    final page2 = Uint8List.fromList(List.filled(4, 9));

    test('openai-compatible：一条消息里按页序放多个 image_url', () {
      final req = OpenAiCompatibleProvider().buildRequest(
          jpegBytesList: [bytes, page2], prompt: 'p', config: config);
      final content =
          ((req.body['messages'] as List).first as Map)['content'] as List;
      expect(content.length, 3, reason: 'text + 两张图');
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(content[2]['type'], 'image_url');
      expect(((content[1] as Map)['image_url'] as Map)['url'],
          endsWith(base64Encode(bytes)));
      expect(((content[2] as Map)['image_url'] as Map)['url'],
          endsWith(base64Encode(page2)), reason: '页序必须与传入顺序一致');
    });

    test('anthropic：多个 image 块，文本在最后', () {
      final req = AnthropicProvider().buildRequest(
          jpegBytesList: [bytes, page2], prompt: 'p', config: config);
      final content =
          ((req.body['messages'] as List).first as Map)['content'] as List;
      expect(content.length, 3);
      expect(content[0]['type'], 'image');
      expect(content[1]['type'], 'image');
      expect(content[2], {'type': 'text', 'text': 'p'});
      expect(((content[0] as Map)['source'] as Map)['data'], base64Encode(bytes));
      expect(((content[1] as Map)['source'] as Map)['data'],
          base64Encode(page2));
    });

    test('gemini：多个 inline_data part', () {
      final req = GeminiProvider().buildRequest(
          jpegBytesList: [bytes, page2], prompt: 'p', config: config);
      final parts =
          ((req.body['contents'] as List).first as Map)['parts'] as List;
      expect(parts.length, 3);
      expect((parts[2] as Map)['text'], 'p');
      expect(((parts[1] as Map)['inline_data'] as Map)['data'],
          base64Encode(page2));
    });

    test('单页等价于原来的单图请求', () {
      final req = OpenAiCompatibleProvider()
          .buildRequest(jpegBytesList: [bytes], prompt: 'p', config: config);
      final content =
          ((req.body['messages'] as List).first as Map)['content'] as List;
      expect(content.length, 2);
    });
  });

  group('响应文本抽取（extractContentText）', () {
    test('OpenAI 兼容形态', () {
      expect(
        extractContentText({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'hello'}
            }
          ]
        }),
        'hello',
      );
    });

    test('OpenAI content 为分段数组', () {
      expect(
        extractContentText({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': 'a'},
                  {'type': 'text', 'text': 'b'},
                ]
              }
            }
          ]
        }),
        'ab',
      );
    });

    test('Anthropic 形态', () {
      expect(
        extractContentText({
          'content': [
            {'type': 'text', 'text': '答案'},
          ]
        }),
        '答案',
      );
    });

    test('Gemini 形态', () {
      expect(
        extractContentText({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'x'},
                  {'text': 'y'},
                ]
              }
            }
          ]
        }),
        'xy',
      );
    });
  });

  group('AiConfig 安全序列化', () {
    test('toSecureJson 不含 apiKey', () {
      final json = config.toSecureJson();
      expect(json.containsKey('api_key'), isFalse);
      expect(json.toString().contains('sk-test'), isFalse);
    });
  });
}
