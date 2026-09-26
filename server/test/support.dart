import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quizsync_server/quizsync_server_core.dart';

/// 单测用的 AI 替身：返回固定文本或抛固定异常，**绝不发真实网络请求**。
class ScriptedProvider extends QuizAiProvider {
  String text;
  AiException? failure;
  Duration delay;

  int calls = 0;
  int lastImageCount = 0;

  ScriptedProvider(this.text, {this.failure, this.delay = Duration.zero});

  @override
  String get id => 'scripted';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    calls++;
    lastImageCount = jpegBytesList.length;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final f = failure;
    if (f != null) throw f;
    return AiRawResponse(text: text, latencyMs: 7);
  }
}

/// 一份合法的 AI 返回（两道题：单选 + 主观）。
const String kFixtureAiText = '''
{
  "questions": [
    {
      "question_no": "12",
      "material": null,
      "stem": "下列说法正确的是",
      "type": "single",
      "options": [{"label": "A", "text": "甲"}, {"label": "B", "text": "乙"}],
      "answer": {"choice": ["B"], "text": null},
      "analysis": "因为 B 对。",
      "confidence": 0.9,
      "need_review": false,
      "has_answer_in_image": false,
      "incomplete": false,
      "answer_is_guess": false,
      "warnings": []
    },
    {
      "question_no": null,
      "material": null,
      "stem": "简述光合作用的意义",
      "type": "subjective",
      "options": [],
      "answer": {"choice": null, "text": "①制造有机物\\n②释放氧气"},
      "analysis": "略",
      "confidence": 0.8,
      "need_review": false,
      "has_answer_in_image": false,
      "incomplete": false,
      "answer_is_guess": false,
      "warnings": []
    }
  ]
}
''';

/// 一张最小的合法 JPEG（1×1 灰点）——不是真图也能走完协议（服务端不解码）。
final Uint8List kJpegBytes = Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00, //
  0x03, 0x02, 0x02, 0x02, 0x02, 0x02, 0x03, 0x02, 0x02, 0x02, 0x03, 0x03,
  0x03, 0x03, 0x04, 0x06, 0x04, 0x04, 0x04, 0x04, 0x08, 0x06, 0x06, 0x05,
  0x06, 0x09, 0x08, 0x0A, 0x0A, 0x09, 0x08, 0x09, 0x09, 0x0A, 0x0C, 0x0F,
  0x0C, 0x0A, 0x0B, 0x0E, 0x0B, 0x09, 0x09, 0x0D, 0x11, 0x0D, 0x0E, 0x0F,
  0x10, 0x10, 0x11, 0x10, 0x0A, 0x0C, 0x12, 0x13, 0x12, 0x10, 0x13, 0x0F,
  0x10, 0x10, 0x10, //
  0xFF, 0xC9, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11,
  0x00, //
  0xFF, 0xCC, 0x00, 0x06, 0x00, 0x10, 0x10, 0x05, //
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, //
  0x7F, 0xFF, 0xD9,
]);

/// 极简 HTTP 客户端（协议测试用；不依赖 Dio）。
class TestHttp {
  final int port;
  String? token;

  TestHttp(this.port, {this.token});

  Uri _uri(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Map<String, String> get headers => {
        if (token != null) 'Authorization': 'Bearer $token',
        'X-QS-Client-Version': '1.0.0',
      };

  Future<({int status, Map<String, dynamic> body})> get(String path) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(_uri(path));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      return (status: resp.statusCode, body: _decode(text));
    } finally {
      client.close(force: true);
    }
  }

  Future<({int status, Map<String, dynamic> body})> postJson(
      String path, Object body,
      {Map<String, String> extraHeaders = const {}}) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(_uri(path));
      headers.forEach((k, v) => req.headers.set(k, v));
      extraHeaders.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      return (status: resp.statusCode, body: _decode(text));
    } finally {
      client.close(force: true);
    }
  }

  Future<({int status, Map<String, dynamic> body})> post(String path,
          {Map<String, String> extraHeaders = const {}}) =>
      postJson(path, const {}, extraHeaders: extraHeaders);

  Future<({int status, Map<String, dynamic> body})> delete(String path) async {
    final client = HttpClient();
    try {
      final req = await client.deleteUrl(_uri(path));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      return (status: resp.statusCode, body: _decode(text));
    } finally {
      client.close(force: true);
    }
  }

  /// 下载二进制（`GET /images/<hash>` 返回的是 JPEG 字节，不能按 UTF-8 解）。
  Future<({int status, List<int> bytes})> getBytes(String path) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(_uri(path));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final chunks = <int>[];
      await for (final chunk in resp) {
        chunks.addAll(chunk);
      }
      return (status: resp.statusCode, bytes: chunks);
    } finally {
      client.close(force: true);
    }
  }

  /// multipart 上传（protocol.md 3.2）。
  Future<({int status, Map<String, dynamic> body})> uploadImage(
      Uint8List bytes) async {
    const boundary = '----quizsyncTest';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="shot.jpg"\r\n'
        'Content-Type: image/jpeg\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final client = HttpClient();
    try {
      final req = await client.postUrl(_uri('/api/v1/images'));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType =
          ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      req.add(head);
      req.add(bytes);
      req.add(tail);
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      return (status: resp.statusCode, body: _decode(text));
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _decode(String text) {
    if (text.isEmpty) return const {};
    try {
      final v = jsonDecode(text);
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// 收集 WS 消息的小工具（`await ws.waitFor('task_result')`）。
class TestSocket {
  final WebSocket socket;
  final List<Map<String, dynamic>> received = [];
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  TestSocket._(this.socket);

  static Future<TestSocket> connect(int port, String token) async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:$port/ws',
      headers: {'Authorization': 'Bearer $token', 'X-QS-Client-Version': '1.0.0'},
    );
    final ts = TestSocket._(socket);
    socket.listen((raw) {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map) {
        final msg = Map<String, dynamic>.from(decoded);
        ts.received.add(msg);
        ts._controller.add(msg);
      }
    });
    return ts;
  }

  /// 等一条指定 type 的消息（超时抛 StateError，避免测试默默挂住）。
  Future<Map<String, dynamic>> waitFor(String type,
      {Duration timeout = const Duration(seconds: 5)}) async {
    for (final msg in received) {
      if (msg['type'] == type) return msg;
    }
    return _controller.stream
        .firstWhere((m) => m['type'] == type)
        .timeout(timeout, onTimeout: () {
      throw StateError('等不到 $type，已收到：${received.map((m) => m['type']).toList()}');
    });
  }

  Future<void> close() => socket.close();
}
