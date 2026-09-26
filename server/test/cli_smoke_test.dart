import 'dart:convert';
import 'dart:io';

import 'package:quizsync_server/src/cli.dart';
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/constants.dart';
import 'package:quizsync_server/src/terminal.dart';
import 'package:test/test.dart';

/// CLI 冒烟：真的把 [ServerApp] 跑起来一次（非交互模式），
/// 断言它能起服务、写配置、印面板。
///
/// 这条用例的价值在于覆盖「组装」那一层 —— 单元测试都不碰 `ServerApp.run`，
/// 曾经有一个 `late final config` 被重复赋值导致的启动崩溃就是这样漏掉的。
void main() {
  test('非交互启动：起服务 + 写配置 + 印面板 + 可正常停止', () async {
    final temp = Directory.systemTemp.createTempSync('quizsync-server-cli');
    final out = StringBuffer();
    final terminal = Terminal.buffer(out);
    final args = parseCliArgs([
      '--config', temp.path,
      '--port', '0',
      '--api-key', 'smoke-key',
      '--base-url', 'http://127.0.0.1:1/v1',
      '--model', 'smoke-model',
      '--no-hotkeys',
      '--no-qr',
    ]);

    final app = ServerApp(terminal: terminal, args: args);
    try {
      final code = await app.run(interactive: false);
      expect(code, 0);
      final text = out.toString();
      expect(text, contains('$kServerProductName v$kServerVersion'));
      expect(text, contains('运行中'));
      expect(text, contains('已配置'));
      expect(text, contains('smoke-model'));
      // 端口 0 = 随机端口，服务器必须真的起来了。
      expect(app.server.port, isNotNull);
      expect(app.server.port, greaterThan(0));
      // 配置落盘并且带着刚传进来的值。
      expect(app.paths.configFile.existsSync(), isTrue);
      final saved = await app.paths.load();
      expect(saved!.apiKey, 'smoke-key');
      expect(saved.model, 'smoke-model');
      // 热键用默认值（F8 截屏识别 / F9 多页模式，只有两条）。
      expect(saved.hotkeyCapture, 'F8');
      expect(saved.hotkeyMultipage, 'F9');
      expect(text, contains('截屏识别'));
      expect(text, contains('F8'));
      // 启动标识（用户要求：启动一次后要留痕）。
      expect(text, contains('第 1 次启动'));
      expect(text, contains('运行'));
      // 状态里也能看到启动次数（存进 state.json 的 stats）。
      final state = jsonDecode(
          await File(app.paths.stateFile.path).readAsString()) as Map;
      expect((state['stats'] as Map)['run_count'], 1);
      // 中文提示块（用户要求：热键、配对方法、更多命令都要讲清楚）。
      expect(text, contains('怎么用'));
      expect(text, contains('手机配对'));
      expect(text, contains('多页识别'));
      expect(text, contains('更多命令'));
      // 运行文件要写出来，--stop 才能找到这个实例。
      expect(app.paths.runtimeFile.existsSync(), isTrue);
    } finally {
      await app.server.stop();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  });

  test('升级迁移：老配置（三个动作那套）换成新的两个动作方案', () async {
    final temp = Directory.systemTemp.createTempSync('quizsync-server-cli-old');
    final paths = ConfigPaths(temp);
    await paths.ensure();
    // 模拟上一版留下的配置（Ctrl+Q / Ctrl+Shift+A / Ctrl+Shift+S，且带旧键名）。
    await File(paths.configFile.path).writeAsString('''
{
  "provider": "openai-compatible",
  "base_url": "https://api.deepseek.com",
  "api_key": "k",
  "model": "m",
  "port": 8765,
  "hotkey_capture": "Ctrl+Q",
  "hotkey_append": "Ctrl+Shift+A",
  "hotkey_finish": "Ctrl+Shift+S"
}
''');
    final out = StringBuffer();
    final app = ServerApp(
      terminal: Terminal.buffer(out),
      args: parseCliArgs([
        '--config', temp.path,
        '--port', '0',
        '--no-hotkeys',
        '--no-qr',
      ]),
    );
    try {
      expect(await app.run(interactive: false), 0);
      final saved = await paths.load();
      expect(saved!.hotkeyCapture, 'F8');
      expect(saved.hotkeyMultipage, 'F9');
      expect(out.toString(), contains('热键方案已更新为'));
    } finally {
      await app.server.stop();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  });

  test('命令行参数解析：未知参数与缺值都报错', () {
    expect(() => parseCliArgs(['--bogus']), throwsA(isA<FormatException>()));
    expect(() => parseCliArgs(['--port']), throwsA(isA<FormatException>()));
    expect(() => parseCliArgs(['--port', 'abc']), throwsA(isA<FormatException>()));
    final args = parseCliArgs([
      '--api-key', 'k',
      '--provider', 'anthropic',
      '--base-url', 'https://x',
      '--model', 'm',
      '--port', '9000',
      '--config', r'D:\tmp\cfg',
      '--no-qr',
      '--no-hotkeys',
    ]);
    expect(args.apiKey, 'k');
    expect(args.provider, 'anthropic');
    expect(args.baseUrl, 'https://x');
    expect(args.model, 'm');
    expect(args.port, 9000);
    expect(args.configPath, r'D:\tmp\cfg');
    expect(args.printQr, isFalse);
    expect(args.registerHotkeys, isFalse);
    expect(args.help, isFalse);
    expect(parseCliArgs(['--help']).help, isTrue);
    expect(parseCliArgs(['-v']).version, isTrue);
  });
}
