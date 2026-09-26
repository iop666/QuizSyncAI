import 'dart:convert';
import 'dart:io';

import 'package:quizsync_server/quizsync_server_core.dart';
import 'package:quizsync_server/src/cli.dart';
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/engine.dart';
import 'package:quizsync_server/src/server.dart';
import 'package:quizsync_server/src/store.dart';
import 'package:quizsync_server/src/tasks.dart';
import 'package:quizsync_server/src/terminal.dart';
import 'package:test/test.dart';

import 'support.dart';

/// 后台运行（`hidden` / `--hidden`）之后的「重新呼出命令行界面」：
///
///   · 服务端开放一个**只认回环 + 控制令牌**的 `POST /api/v1/console`；
///   · 用户再打开一次 exe 时，[attachToRunningServer] 靠数据目录里的 `runtime.json`
///     找到那个实例，把每条命令送过去执行、把输出原样打在自己窗口里。
///
/// 这一组测试走的是**真 HTTP + 真 runtime.json**，只有「敲键盘」那一段没法自动化
/// （测试进程里没有可交互 stdin），所以直接测两头的函数与端点。
void main() {
  group('本机命令行转发（POST /api/v1/console）', () {
    late Directory temp;
    late ConfigPaths paths;
    late ServerStore store;
    late QuizSyncServer server;
    late int port;
    late List<String> received;

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('quizsync-server-console');
      paths = ConfigPaths(temp);
      store = await ServerStore.open(paths);
      received = [];
      final log = Terminal.buffer(StringBuffer());
      final engine = RecognitionEngine(
        deviceId: store.deviceId,
        providerOf: (_) => ScriptedProvider(kFixtureAiText),
      );
      late final ServerTasks tasks;
      late final QuizSyncServer srv;
      tasks = ServerTasks(
        store: store,
        engine: engine,
        configProvider: () => const AiConfig(
          providerId: 'openai-compatible',
          baseUrl: 'https://example.invalid',
          apiKey: 'test-key',
          model: 'test-model',
        ),
        onUpdate: (taskId, status, sessionId, imageCount) =>
            srv.notifyTaskUpdate(taskId, status, sessionId,
                imageCount: imageCount),
        log: log,
      );
      srv = QuizSyncServer(
        store: store,
        tasks: tasks,
        log: log,
        options: const ServerOptions(preferredPort: 0),
        controlToken: 'probe-control-token',
      );
      // 真实运行时这个回调是 ServerApp.handleRemoteCommand（CLI 的窗口命令处理器）。
      srv.onConsoleCommand = (command) async {
        received.add(command);
        return '输出：$command\n';
      };
      server = srv;
      port = await server.start();
      // 真实实例启动时会写它；「重新打开的那个窗口」正是靠它找到这个进程。
      await paths.runtimeFile.writeAsString(jsonEncode({
        'pid': pid,
        'port': port,
        'control_token': 'probe-control-token',
        'version': '1.0.0',
      }));
    });

    tearDown(() async {
      await server.stop();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('回环 + 正确令牌：命令送到正在跑的实例，输出原样带回', () async {
      final runtime = await findRunningServer(paths);
      expect(runtime, isNotNull);
      expect(runtime!['port'], port);
      expect(runtime['pid'], pid);

      final output = await sendConsoleCommand(
          port: port, token: 'probe-control-token', command: 'status');
      expect(output, '输出：status\n');
      expect(received, ['status']);
    });

    test('令牌不对：403，命令一个字都不执行', () async {
      final http = TestHttp(port);
      final resp = await http.postJson('/api/v1/console', {'command': 'status'},
          extraHeaders: {'X-QS-Control': 'wrong-token'});
      expect(resp.status, 403);
      expect(received, isEmpty);
    });

    test('没带令牌：403', () async {
      final http = TestHttp(port);
      final resp =
          await http.postJson('/api/v1/console', {'command': 'status'});
      expect(resp.status, 403);
      expect(received, isEmpty);
    });

    test('请求体不是 JSON 对象：400（不执行任何命令）', () async {
      final http = TestHttp(port);
      final resp = await http.postJson('/api/v1/console', ['status'],
          extraHeaders: {'X-QS-Control': 'probe-control-token'});
      expect(resp.status, 400);
      expect(received, isEmpty);
    });

    test('实例没开放命令行：501', () async {
      server.onConsoleCommand = null;
      final output = await sendConsoleCommand(
          port: port, token: 'probe-control-token', command: 'status');
      expect(output, contains('501'));
      expect(received, isEmpty);
    });

    test('实例已经不在时：findRunningServer 返回 null（窗口照常启动新实例）', () async {
      await server.stop();
      expect(await findRunningServer(paths), isNull);
      // runtime.json 还在（进程被强杀时会留下它），但端口已经没人应答。
      expect(await paths.runtimeFile.exists(), isTrue);
    });

    test('runtime.json 损坏：当成没在跑，不抛异常', () async {
      await server.stop();
      await paths.runtimeFile.writeAsString('{ 这不是 JSON');
      expect(await findRunningServer(paths), isNull);
    });

    test('没有实例时 attachToRunningServer 返回 null，不打印任何东西', () async {
      await server.stop();
      final out = StringBuffer();
      final code = await attachToRunningServer(Terminal.buffer(out),
          configPath: temp.path);
      expect(code, isNull);
      expect(out.toString(), isEmpty);
    });

    test('--console 强制但没实例：说一句「按常规启动」，仍然返回 null', () async {
      await server.stop();
      final out = StringBuffer();
      final code = await attachToRunningServer(Terminal.buffer(out),
          configPath: temp.path, force: true);
      expect(code, isNull);
      expect(out.toString(), contains('按常规启动'));
    });
  });

  group('纯后台运行（--background）的启动前检查', () {
    late Directory temp;
    late ConfigPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('quizsync-server-bg');
      paths = ConfigPaths(temp);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('什么都没配：告诉用户缺 AI', () async {
      expect(await backgroundBlockReason(paths), '还没有配置 AI');
    });

    test('配了 AI、没配对手机：告诉用户缺手机', () async {
      await paths.save(ServerConfig(apiKey: 'sk-test'));
      expect(await backgroundBlockReason(paths), '还没有配对过任何手机');
    });

    test('配了 AI 且有一台已配对手机：放行', () async {
      await paths.save(ServerConfig(apiKey: 'sk-test'));
      final store = await ServerStore.open(paths);
      store.devices['phone-1'] = PairedDevice(
        info: DeviceInfo(
          deviceId: 'phone-1',
          name: 'Pixel 7',
          platform: 'android',
          pairedAt: 1,
        ),
        tokenHash: 'hash',
      );
      await store.save();
      expect(await backgroundBlockReason(paths), isNull);
    });

    test('只剩被吊销的手机：仍然算没配对过', () async {
      await paths.save(ServerConfig(apiKey: 'sk-test'));
      final store = await ServerStore.open(paths);
      store.devices['phone-1'] = PairedDevice(
        info: DeviceInfo(
          deviceId: 'phone-1',
          name: 'Pixel 7',
          platform: 'android',
          pairedAt: 1,
          revokedAt: 2,
        ),
        tokenHash: 'hash',
      );
      await store.save();
      expect(await backgroundBlockReason(paths), '还没有配对过任何手机');
    });
  });

  group('启动参数', () {
    test('--background / -b / --console 都能解析', () {
      expect(parseCliArgs(['--background']).background, isTrue);
      expect(parseCliArgs(['-b']).background, isTrue);
      expect(parseCliArgs(['--console']).console, isTrue);
      final none = parseCliArgs(const []);
      expect(none.background, isFalse);
      expect(none.console, isFalse);
    });

    test('--hidden 与 --background 是两件事', () {
      final hidden = parseCliArgs(['--hidden']);
      expect(hidden.hidden, isTrue);
      expect(hidden.background, isFalse);
      final background = parseCliArgs(['--background']);
      expect(background.background, isTrue);
      expect(background.hidden, isFalse);
    });
  });
}
