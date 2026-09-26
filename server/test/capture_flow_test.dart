import 'dart:io';
import 'dart:typed_data';

import 'package:quizsync_server/quizsync_server_core.dart';
import 'package:quizsync_server/src/capture.dart';
import 'package:quizsync_server/src/capture_flow.dart';
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/constants.dart';
import 'package:quizsync_server/src/engine.dart';
import 'package:quizsync_server/src/server.dart';
import 'package:quizsync_server/src/store.dart';
import 'package:quizsync_server/src/tasks.dart';
import 'package:quizsync_server/src/terminal.dart';
import 'package:test/test.dart';

import 'support.dart';

/// 两个热键动作的**行为**测试（真流水线 + 假截屏 + 假 AI，不碰真屏幕）。
///
/// 覆盖用户 1.0.0 优化第 5 条定稿的运行模式：
///   - 截屏识别键：不在多页 → 单张识别；在多页 → 结束多页并上传已抓的图；
///   - 多页模式键：进入并抓第一张、继续追加、满 6 张自动上传。
void main() {
  late Directory temp;
  late ConfigPaths paths;
  late ServerStore store;
  late ScriptedProvider provider;
  late ServerTasks tasks;
  late QuizSyncServer server;
  late CaptureFlow flow;
  late StringBuffer out;

  /// 每次截图给出**不同**像素，避免命中「同图复用」。
  var shot = 0;
  CapturedScreen nextScreen() {
    shot++;
    final bgra = Uint8List(4 * 4 * 4);
    for (var i = 0; i < bgra.length; i++) {
      bgra[i] = (i * 7 + shot * 31) % 256;
    }
    return CapturedScreen(width: 4, height: 4, bgra: bgra);
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('quizsync-flow');
    paths = ConfigPaths(temp);
    out = StringBuffer();
    final log = Terminal.buffer(out);
    store = await ServerStore.open(paths);
    provider = ScriptedProvider(kFixtureAiText);
    tasks = ServerTasks(
      store: store,
      engine: RecognitionEngine(
        deviceId: store.deviceId,
        providerOf: (_) => provider,
      ),
      configProvider: () => const AiConfig(
        providerId: 'openai-compatible',
        baseUrl: 'https://example.invalid',
        apiKey: 'k',
        model: 'm',
      ),
      onUpdate: (taskId, status, sessionId, imageCount) =>
          server.notifyTaskUpdate(taskId, status, sessionId,
              imageCount: imageCount),
      log: log,
    );
    server = QuizSyncServer(
      store: store,
      tasks: tasks,
      log: log,
      options: const ServerOptions(preferredPort: 0),
    );
    flow = CaptureFlow(
      capture: ScreenCapture(),
      tasks: tasks,
      store: store,
      server: server,
      log: log,
      captureScreen: nextScreen,
    );
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('截屏识别键：不在多页模式 → 截一张立刻识别', () async {
    await flow.onCapture();
    expect(provider.calls, 1);
    expect(provider.lastImageCount, 1);
    expect(flow.pendingPages, 0);
    expect(flow.inMultipage, isFalse);
    expect(out.toString(), contains('单张截屏识别'));
    expect(out.toString(), contains('识别完成'));
  });

  test('多页模式键：第一次进入并抓第 1 张，继续按追加（不调 AI）', () async {
    await flow.onMultipage();
    expect(flow.pendingPages, 1);
    expect(provider.calls, 0, reason: '攒页阶段不该调 AI');
    await flow.onMultipage();
    expect(flow.pendingPages, 2);
    expect(provider.calls, 0);
    expect(out.toString(), contains('多页模式 1/$kHardMaxPagesPerTask 张'));
    expect(out.toString(), contains('多页模式 2/$kHardMaxPagesPerTask 张'));
  });

  test('多页模式下按截屏识别键 = 结束多页并上传已抓的全部图片', () async {
    await flow.onMultipage();
    await flow.onMultipage();
    await flow.onMultipage();
    expect(flow.pendingPages, 3);

    await flow.onCapture();
    expect(provider.calls, 1);
    expect(provider.lastImageCount, 3, reason: '三张一起送 AI');
    expect(flow.pendingPages, 0);
    expect(out.toString(), contains('结束多页模式：上传已抓取的 3 张图片识别'));
  });

  test('攒满 6 张自动上传识别（不用再按识别键）', () async {
    for (var i = 0; i < kHardMaxPagesPerTask; i++) {
      await flow.onMultipage();
    }
    expect(provider.calls, 1);
    expect(provider.lastImageCount, kHardMaxPagesPerTask);
    expect(flow.pendingPages, 0, reason: '自动上传后回到单张模式');
    expect(out.toString(), contains('已抓满 $kHardMaxPagesPerTask 张，自动上传识别'));
  });

  test('识别完成后可以重新开始多页', () async {
    await flow.onMultipage();
    await flow.onCapture();
    expect(flow.pendingPages, 0);
    await flow.onMultipage();
    expect(flow.pendingPages, 1);
    await flow.onMultipage();
    expect(flow.pendingPages, 2);
  });

  test('页面都落在 Server 合集里', () async {
    await flow.onCapture();
    final session = store.sessions.values.last;
    expect(session.session.collectionId, store.collection.collectionId);
    expect(store.collection.name, kDefaultCollectionName);
    expect(store.collection.name, 'Server');
  });

  test('截图失败只写日志，不影响服务', () async {
    late CaptureFlow broken;
    broken = CaptureFlow(
      capture: ScreenCapture(),
      tasks: tasks,
      store: store,
      server: server,
      log: Terminal.buffer(out),
      captureScreen: () => throw StateError('boom'),
    );
    await broken.onCapture();
    await broken.onMultipage();
    expect(provider.calls, 0);
    expect(broken.pendingPages, 0);
    expect(out.toString(), contains('截图失败'));
  });
}
