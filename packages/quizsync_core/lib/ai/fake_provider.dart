import 'dart:io';
import 'dart:typed_data';

import 'provider.dart';

/// 假 provider：从 fixture 文件读固定响应。
/// **单测与回环测试的唯一网络替身，绝不发真实网络请求。**
class FakeAiProvider extends QuizAiProvider {
  /// fixture 文件的绝对路径。
  final String fixturePath;

  /// 可注入的延迟（模拟真实耗时）。
  final Duration delay;

  FakeAiProvider(this.fixturePath, {this.delay = Duration.zero});

  int callCount = 0;

  /// 最近一次请求收到的图片数量（多页用例断言用）。
  int lastImageCount = 0;

  @override
  String get id => 'fake';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    callCount++;
    lastImageCount = jpegBytesList.length;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final text = await File(fixturePath).readAsString();
    return AiRawResponse(text: text, latencyMs: 42);
  }
}
