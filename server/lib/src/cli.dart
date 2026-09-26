import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'capture.dart';
import 'capture_flow.dart';
import 'config.dart';
import 'console_window.dart';
import 'constants.dart';
import 'engine.dart';
import 'hotkey_service.dart';
import 'hotkeys.dart';
import 'net_info.dart';
import 'qr_terminal.dart';
import 'server.dart';
import 'status_panel.dart';
import 'store.dart';
import 'tasks.dart';
import 'terminal.dart';

/// 命令行参数。
class CliArgs {
  final String? configPath;
  final int? port;
  final String? apiKey;
  final String? provider;
  final String? baseUrl;
  final String? model;
  final bool printQr;
  final bool registerHotkeys;

  /// 后台无窗口运行（`--hidden`）：**脱离控制台**，窗口消失，关掉终端也不影响它。
  final bool hidden;

  /// 完全独立的纯后台进程（`--background`）：另起一个没有控制台的自己，本次启动退出。
  final bool background;

  /// 已经有实例在跑时，要求当它的命令行窗口（`--console`；默认也会自动这么做）。
  final bool console;

  /// 请求**正在运行**的那个实例优雅退出（`--stop`）。
  final bool stop;

  /// 看看现在有没有实例在跑（`--status`）。
  final bool status;

  final bool help;
  final bool version;

  const CliArgs({
    this.configPath,
    this.port,
    this.apiKey,
    this.provider,
    this.baseUrl,
    this.model,
    this.printQr = true,
    this.registerHotkeys = true,
    this.hidden = false,
    this.background = false,
    this.console = false,
    this.stop = false,
    this.status = false,
    this.help = false,
    this.version = false,
  });
}

/// 解析命令行（未知参数直接报错退出，不要静默忽略）。
CliArgs parseCliArgs(List<String> argv) {
  String? config;
  int? port;
  String? apiKey;
  String? provider;
  String? baseUrl;
  String? model;
  var qr = true;
  var hotkeys = true;
  var hidden = false;
  var background = false;
  var console = false;
  var stop = false;
  var status = false;
  var help = false;
  var version = false;

  String valueOf(String flag, int i) {
    if (i + 1 >= argv.length) {
      throw FormatException('$flag 缺少参数值');
    }
    return argv[i + 1];
  }

  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    switch (a) {
      case '--help':
      case '-h':
        help = true;
      case '--version':
      case '-v':
        version = true;
      case '--config':
        config = valueOf(a, i);
        i++;
      case '--port':
        port = int.tryParse(valueOf(a, i));
        if (port == null) throw FormatException('--port 需要数字');
        i++;
      case '--api-key':
        apiKey = valueOf(a, i);
        i++;
      case '--provider':
        provider = valueOf(a, i);
        i++;
      case '--base-url':
        baseUrl = valueOf(a, i);
        i++;
      case '--model':
        model = valueOf(a, i);
        i++;
      case '--no-qr':
        qr = false;
      case '--no-hotkeys':
        hotkeys = false;
      case '--hidden':
      case '-d':
        hidden = true;
      case '--background':
      case '-b':
        background = true;
      case '--console':
        console = true;
      case '--stop':
        stop = true;
      case '--status':
        status = true;
      default:
        throw FormatException('未知参数：$a（用 --help 看用法）');
    }
  }
  return CliArgs(
    configPath: config,
    port: port,
    apiKey: apiKey,
    provider: provider,
    baseUrl: baseUrl,
    model: model,
    printQr: qr,
    registerHotkeys: hotkeys,
    hidden: hidden,
    background: background,
    console: console,
    stop: stop,
    status: status,
    help: help,
    version: version,
  );
}

/// 用法说明（默认热键直接从常量取，避免文案与配置默认值漂移）。
final String kUsage = '''
$kServerProductName v$kServerVersion — 截图 → AI → 手机

用法：QuizSyncAI_Server.exe [选项]

选项：
  --api-key <key>        AI API Key（不给则在首次运行时按引导输入）
  --provider <id>        openai-compatible | anthropic | gemini（默认 openai-compatible）
  --base-url <url>       AI 服务地址（默认 https://api.deepseek.com）
  --model <name>         AI 模型名（默认 deepseek-flash）
  --port <n>             监听端口（默认 $kDefaultPort，被占用则往后探测 5 个）
  --config <path>        配置目录或 config.json 的路径
  --hidden, -d           后台运行：AI 已配置且配对过手机后，本进程脱离控制台，
                         窗口消失、关掉终端也不影响它（日志继续写数据目录的 server.log）
  --background, -b       纯后台：另起一个完全没有控制台的自己，本次启动立刻返回
                         （适合放「启动」文件夹 / 快捷方式，开机就悄悄跑起来）
  --console              不起新服务，直接连上正在运行的那个实例，给它当命令行窗口
  --stop                 让正在运行的那个实例退出
  --status               看看现在有没有实例在跑、跑在哪个端口、是第几次启动
  --no-qr                不打印配对二维码
  --no-hotkeys           不注册全局热键（调试用）
  -v, --version          打印版本
  -h, --help             打印本说明

⚠️ --hidden / --background / --console / --stop / --status 是启动参数：在命令行
   或快捷方式里加，不是启动后在窗口里敲的命令（窗口里敲会提示你正确的用法）。

关于「窗口没了以后怎么再看到命令行」：
  · 窗口里输入 hidden → 窗口真的消失，服务继续在后台跑；
  · 想再看命令行：再打开一次 QuizSyncAI_Server.exe（双击即可）。它发现已经有实例
    在跑，就不再起第二个服务，而是直接给那个实例当命令行窗口 —— 界面上会写明
    「后台实例正在运行（PID / 端口）」，你在这里敲的命令都送到它身上执行。
  · 停止服务：在那个窗口里输入 stop，或在别处执行 QuizSyncAI_Server.exe --stop。

运行后可输入的命令（直接敲 help 也能看到）：
  help                                    命令列表
  status                                  重新显示状态
  qr                                      重新显示配对二维码
  pair                                    刷新配对码并重新显示二维码
  hidden                                  转后台运行（窗口消失，服务继续跑）
  hotkey capture <组合键>                 改「截屏识别」热键
  hotkey multipage <组合键>               改「多页模式」热键
  hotkeys reset                           两个热键恢复默认
  devices                                 已配对手机
  ai                                      显示当前 AI 配置
  set-api-key <key> / set-model <name> / set-base-url <url> / set-provider <id>
                                          修改 AI 配置
  stop                                    停止服务
  quit                                    退出（后台实例运行时 = 只关掉这个命令行窗口）

热键（两个动作，一个动作一条键）：
  截屏识别 ${ServerConfig.kDefaultHotkeyCapture}
     单张直接识别；多页模式下按它 = 结束多页，把已抓的图一起上传识别。
  多页模式 ${ServerConfig.kDefaultHotkeyMultipage}
     第一次按进入多页并抓第 1 张，继续按追加；攒满 $kHardMaxPagesPerTask 张自动上传识别。
''';

/// `--stop`：让**正在后台运行**的那个实例优雅退出。
///
/// 做法：读它启动时写的运行文件（`runtime.json`，里面有端口与一次性控制令牌），
/// 向本机回环地址发一个 `POST /api/v1/shutdown`。服务端会校验「请求来自回环地址
/// **且**令牌正确」，所以局域网里的手机与别的机器都停不了它。
///
/// 背景：`--hidden` 之后控制台窗口没了，用户没法再敲 `quit`、也没法 Ctrl+C，
/// 总得留一条正经的停机路 —— 而不是只能去任务管理器里结束进程。
Future<int> stopRunningServer(Terminal terminal, {String? configPath}) async {
  final paths = ConfigPaths.resolve(override: configPath);
  final file = paths.runtimeFile;
  if (!await file.exists()) {
    terminal.error('没有找到正在运行的服务：${file.path} 不存在');
    terminal.line('（如果它是前台运行的，直接在窗口里敲 quit 或按 Ctrl+C）');
    return 1;
  }
  Map<String, dynamic> info;
  try {
    info = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map);
  } catch (_) {
    terminal.error('运行文件损坏：${file.path}（可手动删掉后重试）');
    return 1;
  }
  final port = (info['port'] as num?)?.toInt();
  final token = info['control_token']?.toString();
  if (port == null || token == null || token.isEmpty) {
    terminal.error('运行文件缺少 port / control_token：${file.path}');
    return 1;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/shutdown'));
    req.headers.set('X-QS-Control', token);
    final resp = await req.close();
    await resp.drain<void>();
    if (resp.statusCode == 200) {
      terminal.log('服务器', '已请求停止（端口 $port），服务正在退出');
      return 0;
    }
    terminal.error('停止请求被拒绝：HTTP ${resp.statusCode}');
    return 1;
  } catch (e) {
    terminal.error('连不上正在运行的服务（端口 $port）：$e');
    terminal.line('（它可能已经退出了；确认没有 QuizSyncAI_Server.exe 在跑就行）');
    return 1;
  } finally {
    client.close(force: true);
  }
}

/// `--status`：不启动任何东西，只回答三个问题 ——
/// 「现在有没有实例在跑」「跑在哪个端口」「这是第几次启动」。
///
/// 后台运行（`--hidden`）之后窗口没了，用户需要一个不靠窗口就能确认它在跑的办法；
/// 这个命令同时也就是那份**启动标识**的对外出口。
Future<int> printServerStatus(Terminal terminal, {String? configPath}) async {
  final paths = ConfigPaths.resolve(override: configPath);

  // 1) 有没有实例在跑（读它启动时写的 runtime.json，并 ping 一下端口）。
  final runtime = await findRunningServer(paths);
  final running = runtime != null;
  final port = runtime?['port'];
  final pid = runtime?['pid'];

  // 2) 启动标识（第几次启动 / 首次 / 上次），读 state.json 里的 stats。
  var runCount = 0;
  String firstText = '（无）';
  String lastText = '（无）';
  try {
    if (await paths.stateFile.exists()) {
      final raw = jsonDecode(await paths.stateFile.readAsString());
      final stats = raw is Map ? raw['stats'] : null;
      if (stats is Map) {
        runCount = (stats['run_count'] as num?)?.toInt() ?? 0;
        final f = (stats['first_run_at'] as num?)?.toInt();
        final l = (stats['last_run_at'] as num?)?.toInt();
        if (f != null) firstText = _formatTime(f);
        if (l != null) lastText = _formatTime(l);
      }
    }
  } catch (_) {}

  terminal.line();
  terminal.line('$kServerProductName v$kServerVersion');
  terminal.line('─' * 46);
  terminal.line('  状态    ${running ? '正在运行' : '未在运行'}');
  if (running) {
    terminal.line('  端口    $port${pid == null ? '' : '（PID $pid）'}');
    terminal.line('  停止    QuizSyncAI_Server.exe --stop');
  }
  terminal.line('  启动    第 $runCount 次 · 首次 $firstText · 上次 $lastText');
  terminal.line('  数据    ${paths.dir.path}');
  terminal.line();
  return 0;
}

// ------------------------------------------------------------
// 已有实例在跑：本次启动不起第二个服务，而是给它当「命令行窗口」
// ------------------------------------------------------------

/// 读 `runtime.json` 并确认那个实例真的还在跑；不在跑就返回 null。
///
/// 返回 `{port, pid, control_token}`。
Future<Map<String, Object?>?> findRunningServer(ConfigPaths paths) async {
  try {
    if (!await paths.runtimeFile.exists()) return null;
    final info = Map<String, dynamic>.from(
        jsonDecode(await paths.runtimeFile.readAsString()) as Map);
    final port = (info['port'] as num?)?.toInt();
    final token = info['control_token']?.toString();
    if (port == null || token == null || token.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/v1/info'));
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode != 200) return null;
      return {
        'port': port,
        'pid': (info['pid'] as num?)?.toInt(),
        'control_token': token,
      };
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    return null; // 运行文件损坏：当作「没在跑」
  }
}

/// 把一条窗口内命令送到**正在运行的那个实例**执行，返回它的输出文本。
///
/// 走 `POST /api/v1/console`（只接受回环地址 + `runtime.json` 里的控制令牌）。
/// 返回 null = 连不上（实例多半已经退出了）。
Future<String?> sendConsoleCommand({
  required int port,
  required String token,
  required String command,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/console'));
    req.headers.set('X-QS-Control', token);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'command': command}));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      return '[错误] 后台实例拒绝了这条命令：HTTP ${resp.statusCode}\n';
    }
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded['output']?.toString() ?? '';
    return '';
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// 已经有实例在跑时：本次启动当它的**命令行窗口**（`--console`，或者用户直接又
/// 双击了一次 exe —— 这正是他想要的「重新呼出命令行界面」）。
///
/// 返回 null 表示「现在没有实例在跑」，调用方照常启动一个新实例。
Future<int?> attachToRunningServer(
  Terminal terminal, {
  String? configPath,
  bool force = false,
}) async {
  final paths = ConfigPaths.resolve(override: configPath);
  final runtime = await findRunningServer(paths);
  if (runtime == null) {
    if (force) terminal.line('现在没有实例在运行，按常规启动一个新实例…');
    return null;
  }
  final port = runtime['port']! as int;
  final pid = runtime['pid'] as int?;
  final token = runtime['control_token']! as String;

  terminal.line();
  terminal.line('$kServerProductName v$kServerVersion');
  terminal.line('─' * 46);
  terminal.line('  后台实例正在运行${pid == null ? '' : '（PID $pid）'} · 端口 $port');
  terminal.line('  这里就是它的命令行：你敲的命令会送到那个进程上执行。');
  terminal.line('  关闭本窗口不影响它；要停它请敲 stop（或执行 --stop）。');
  terminal.line('  输入 help 看全部命令，quit 退出本窗口。');
  terminal.line();

  final input = LineInput();
  while (true) {
    terminal.write('> ');
    final line = await input.next();
    if (line == null) break; // stdin 结束（窗口被关掉）→ 本窗口退出
    final text = line.trim();
    if (text.isEmpty) continue;
    final cmd = text.split(RegExp(r'\s+')).first.toLowerCase();
    if (cmd == 'quit' || cmd == 'exit') {
      terminal.line('（后台实例继续运行；要停它请敲 stop 或执行 --stop）');
      return 0;
    }
    if (cmd == 'hidden' || cmd == 'background' || cmd == 'bg') {
      terminal.line('（服务本来就在独立后台运行 —— 直接关掉本窗口即可，它不受影响）');
      continue;
    }
    final output =
        await sendConsoleCommand(port: port, token: token, command: text);
    if (output == null) {
      terminal.error('连不上后台实例（端口 $port），它可能已经退出了。');
      return 1;
    }
    terminal.write(output.endsWith('\n') ? output : '$output\n');
    if (cmd == 'stop') {
      terminal.line('后台实例正在退出，本窗口关闭。');
      return 0;
    }
  }
  return 0;
}

/// 纯后台运行（`--background`）的门禁：AI 已配置 + 至少配对过一台手机。
///
/// 返回 null = 可以后台运行；否则返回缺什么（中文，直接给用户看）。
/// 纯后台进程没有控制台，缺东西时用户什么也看不到，所以在**启动前**就问清楚。
Future<String?> backgroundBlockReason(ConfigPaths paths) async {
  var aiConfigured = false;
  try {
    if (await paths.configFile.exists()) {
      final raw = jsonDecode(await paths.configFile.readAsString());
      if (raw is Map) {
        aiConfigured =
            ServerConfig.fromJson(Map<String, dynamic>.from(raw)).aiConfigured;
      }
    }
  } catch (_) {}
  if (!aiConfigured) return '还没有配置 AI';

  var paired = false;
  try {
    if (await paths.stateFile.exists()) {
      final raw = jsonDecode(await paths.stateFile.readAsString());
      final devices = raw is Map ? raw['devices'] : null;
      if (devices is List) {
        paired = devices.any((d) => d is Map && d['revoked_at'] == null);
      }
    }
  } catch (_) {}
  if (!paired) return '还没有配对过任何手机';
  return null;
}

/// `--background`：另起一个**完全没有控制台**的自己，本次启动立刻返回。
///
/// 与 `--hidden` 的区别：`--hidden` 是「本进程脱离控制台」（双击时窗口会闪一下），
/// 这个是「重新起一个干净的、根本没有控制台的进程，我这个启动器马上退出」——
/// 放进「启动」文件夹或做快捷方式用它最合适，连黑窗口都不会出现。
Future<int> launchBackgroundServer(Terminal terminal, {String? configPath}) async {
  final paths = ConfigPaths.resolve(override: configPath);

  final running = await findRunningServer(paths);
  if (running != null) {
    terminal.log('后台', '已经有一个实例在运行'
        '（PID ${running['pid']}，端口 ${running['port']}），不再重复启动。');
    terminal.line('  想看它的命令行：再运行一次本程序（或加 --console）');
    terminal.line('  停止服务：QuizSyncAI_Server.exe --stop');
    return 1;
  }

  final reason = await backgroundBlockReason(paths);
  if (reason != null) {
    terminal.error('暂时不能纯后台运行：$reason');
    terminal.line('先正常运行一次（不加参数），跟着引导配好 AI 并扫码配对手机，'
        '之后再用 --background 或窗口里的 hidden。');
    return 1;
  }

  try {
    final child = await Process.start(
      Platform.resolvedExecutable,
      ['--hidden', if (configPath != null) ...['--config', configPath]],
      mode: ProcessStartMode.detached,
    );
    terminal.log('后台', '已在后台启动（PID ${child.pid}），本窗口可以关掉了。');
    terminal.line('  重新看到命令行：再运行一次 QuizSyncAI_Server.exe');
    terminal.line('  看看在不在跑：QuizSyncAI_Server.exe --status');
    terminal.line('  停止服务：QuizSyncAI_Server.exe --stop');
    return 0;
  } catch (e) {
    terminal.error('后台启动失败：$e');
    return 1;
  }
}

/// `2026-09-23 20:15`；同一天只显示时间。
String _formatTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Server 的 CLI 主程序：起服务、注册热键、显示面板、读命令。
class ServerApp {
  /// 输出终端。**不是 final**：执行远端转发来的命令时会临时换成内存缓冲，
  /// 好用一条 HTTP 响应把输出带回用户那个窗口（见 [handleRemoteCommand]）。
  Terminal terminal;
  final CliArgs args;
  final HotkeyRegistrar? hotkeys;

  late final ConfigPaths paths;

  /// 配置会被反复改写（首次输入、命令行覆盖、CLI 命令），所以不能是 final。
  late ServerConfig config;
  late final ServerStore store;
  late final RecognitionEngine engine;
  late final ServerTasks tasks;
  late final QuizSyncServer server;
  late final CaptureFlow flow;

  String lanIp = '127.0.0.1';
  var _shuttingDown = false;

  /// 已经脱离控制台（转后台成功）。此后没有键盘可读，进程靠 stop / --stop 结束。
  bool _detached = false;

  /// 本次是第几次启动（1 = 第一次；启动标识，用户要求）。
  int runIndex = 0;

  /// **本次之前**那一次启动的时间。
  ///
  /// 不能用 `store.lastRunAt`：`noteStartup()` 把它写成「现在」了，状态块里会出现
  /// 「上次 = 本次」，等于没话说（M45f 修）。
  int? _previousRunAt;

  /// runtime.json 是不是本次启动写的（不是就别去删别人的）。
  bool _ownsRuntimeFile = false;

  /// 没拿到运行文件时的复查计时器（原来的实例死了就把文件收回来，见
  /// [_takeOverStaleRuntimeFile]）。
  Timer? _runtimeWatch;

  /// 首次配置问答与命令循环共用同一个 stdin 流（一个流只能有一个监听者）。
  LineInput? _input;
  LineInput get input => _input ??= LineInput();

  ServerApp({required this.terminal, required this.args, this.hotkeys});

  // ------------------------------------------------------------
  // 启动
  // ------------------------------------------------------------

  Future<int> run({bool interactive = true}) async {
    paths = ConfigPaths.resolve(override: args.configPath);

    // 0. 老版本把数据放在 %APPDATA%\QuizSyncAI\Server；现在默认放在 exe 同目录的
    //    应用同名目录。搬一次，免得用户升级后发现「配对没了、历史空了」。
    await paths.migrateLegacyIfNeeded();
    await paths.ensure();

    // 1. 配置：文件 → 命令行覆盖 → （缺 API Key 时）首次交互输入。
    final raw = await paths.loadRaw();
    final wasLegacyConfig = raw != null && ServerConfig.hadLegacySlots(raw);
    // `ServerConfig.fromJson` 内部已经把老的「三个动作」热键迁移成新的两个动作。
    config = raw == null ? ServerConfig() : ServerConfig.fromJson(raw);
    config = config.copyWith(
      port: args.port ?? config.port,
      apiKey: (args.apiKey != null && args.apiKey!.isNotEmpty)
          ? args.apiKey
          : config.apiKey,
      providerId: args.provider ?? config.providerId,
      baseUrl: args.baseUrl ?? config.baseUrl,
      model: args.model ?? config.model,
    );
    if (raw == null || args.apiKey != null || args.port != null || wasLegacyConfig) {
      // 首次生成 / 命令行给了值 / 换了热键方案：立刻落盘，下次启动直接读配置。
      await paths.save(config);
      if (wasLegacyConfig) {
        terminal.log('热键', '热键方案已更新为「截屏识别 ${config.hotkeyCapture}」'
            '与「多页模式 ${config.hotkeyMultipage}」');
      }
    }
    if (!config.aiConfigured) {
      await _firstRunSetup();
    }

    // 2. 状态 + AI 引擎 + 任务流水线。
    store = await ServerStore.open(paths);
    // 本次之前的上次启动时间要在 noteStartup() 覆盖之前取出来。
    final previousRunAt = store.lastRunAt;
    _previousRunAt = previousRunAt;
    runIndex = await store.noteStartup();
    engine = RecognitionEngine(deviceId: store.deviceId);
    tasks = ServerTasks(
      store: store,
      engine: engine,
      configProvider: () => aiConfigOf(
        providerId: config.providerId,
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      ),
      onUpdate: (taskId, status, sessionId, imageCount) =>
          server.notifyTaskUpdate(taskId, status, sessionId,
              imageCount: imageCount),
      log: terminal,
    );
    server = QuizSyncServer(
      store: store,
      tasks: tasks,
      log: terminal,
      options: ServerOptions(preferredPort: config.port),
    );
    server.onStateChanged = _printStatus;
    server.onDeviceConnected = (id, name) => _printStatus();
    server.onDeviceDisconnected = (id, name) => _printStatus();
    // `--stop` 走的就是这条路：本机回环 + 控制令牌 → 优雅停机（等价 quit / Ctrl+C）。
    server.onShutdownRequested = () => unawaited(shutdown(0));
    // 后台运行之后，用户再打开一次本程序得到的是「前端窗口」：它把命令送到这里
    // 执行、把输出带回那个窗口（见 cli.dart 的 attachToRunningServer）。
    server.onConsoleCommand = handleRemoteCommand;

    flow = CaptureFlow(
      capture: ScreenCapture(),
      tasks: tasks,
      store: store,
      server: server,
      log: terminal,
    );

    // 3. 起服务。启动前先看有没有别的实例在跑（两个实例抢同一个端口 / 同一套热键
    //    会让用户以为「按了没反应」，必须明说）。
    final other = await _liveInstance();
    if (other != null) {
      terminal.log('提示', '检测到已经有一个实例在运行'
          '${other['port'] == null ? '' : '（端口 ${other['port']}'
              '${other['pid'] == null ? '' : '，PID ${other['pid']}'}）'}。');
      terminal.line('     要停掉它：QuizSyncAI_Server.exe --stop；'
          '要看它的状态：QuizSyncAI_Server.exe --status；'
          '要给它当命令行窗口：QuizSyncAI_Server.exe --console。');
      terminal.line('     继续启动会占用下一个可用端口，两个实例的热键会互相顶掉。');
    }
    terminal.line();
    try {
      final port = await server.start();
      lanIp = await lanIpAddress();
      await _writeRuntimeFile(port);
    } catch (e) {
      terminal.error('服务启动失败：$e');
      return 1;
    }

    // 启动标识：第几次启动、首次与上次启动时间。
    terminal.log('启动',
        '第 $runIndex 次启动 · 首次 ${_formatTime(store.firstRunAt ?? DateTime.now().millisecondsSinceEpoch)}'
        ' · 上次 ${previousRunAt == null ? '（无）' : _formatTime(previousRunAt)}');

    // 4. 热键（两个动作 × 主键 + 备用键）。
    if (args.registerHotkeys) await _setupHotkeys();

    // 5. 状态 + 配对二维码 + 中文提示（一整块，只印这一次）。
    _printStatus(force: true);
    _printQr();
    _printHints();

    // 5.1 后台模式：**AI 已配置 + 至少配对过一台手机**才脱离控制台，否则用户没法
    //     扫码配对或改配置，窗口一消失等于把人锁在门外。
    if (args.hidden) {
      final reason = _backgroundBlockReason();
      if (reason != null) {
        terminal.log('后台', '--hidden：$reason，先保持窗口可见'
            '（完成首次配置并配对手机后，再启动就会自动后台运行）');
      } else {
        await _enterBackground();
      }
    }

    if (!interactive) return 0;

    // 6. Ctrl+C：停服务、注销热键、保存状态、退出（不留残进程）。
    final sigint = ProcessSignal.sigint.watch().listen((_) {
      unawaited(shutdown(0));
    });
    // 配对码 5 分钟过期；过期且还没有设备连上时自动换一个。只印一行提示 +
    // 新二维码，不再把整块状态重印一遍（那会刷屏）。
    final codeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (server.connectedCount == 0 && server.ensureFreshPairingCode()) {
        terminal.log('手机', '配对码已刷新为 ${server.pairingCode}（新二维码见下）');
        _printQr();
      }
    });

    // 已经脱离控制台：stdin 跟着控制台一起没了，没有键盘可读 —— 挂在这里别返回
    // （返回就会走到下面的 shutdown，等于「转后台之后立刻自己退出」）。
    if (_detached) await _parkForever();

    await _commandLoop();
    codeTimer.cancel();
    await sigint.cancel();
    await shutdown(0);
    return 0;
  }

  // ------------------------------------------------------------
  // 运行文件（无窗口后台模式的 `--stop` 靠它定位本进程）
  // ------------------------------------------------------------

  /// 写 `runtime.json`：pid + 端口 + 控制令牌。退出时删掉。
  ///
  /// **只有第一个实例能拥有它**：真有一个实例在跑时第二个不覆盖，否则 `--stop` /
  /// `--status` 会指到后启动的这个，而先启动的那个反倒没人找得到。
  ///
  /// 「真有一个实例在跑」的判据是**记录里的 PID 还活着**，不是「那个端口有没有人应答」
  /// （M45f 修正）：运行文件里写着旧进程的端口，而那个端口恰好就是本实例这次要用的端口时，
  /// `server.start()` 之后再去 ping 它，答话的其实是**自己** → 误判「已经有一个实例在运行」
  /// → 永远不写运行文件，`--stop` / `--status` 一直指着一个死进程（交付冒烟实测踩到）。
  Future<void> _writeRuntimeFile(int port) async {
    final info = await _readRuntimeInfo();
    final recorded = (info['pid'] as num?)?.toInt();
    if (recorded != null && recorded != pid && _processAlive(recorded)) {
      terminal.log('提示', '已经有一个实例在运行（PID $recorded'
          '${info['port'] == null ? '' : '，端口 ${info['port']}'}），'
          '本次启动不接管 runtime.json（--stop / --status 仍指向它）。');
      // 先启动的那个一旦**被杀掉**（关窗口、任务管理器结束），这份文件就成了没人认领的
      // 僵尸：`--stop` 会拿着它的旧令牌去敲本实例，得到 403。所以隔一会儿复查一次：
      // 只要文件里记的那个 PID 已经不在了，就把这份文件接过来。
      _runtimeWatch = Timer.periodic(const Duration(seconds: 15), (_) {
        if (Platform.environment['QS_RUNTIME_WATCH_DIAG'] == '1') {
          terminal.log('DIAG', '运行文件复查触发');
        }
        unawaited(_takeOverStaleRuntimeFile(port));
      });
      return;
    }
    await _claimRuntimeFile(port);
  }

  /// 读运行文件（不存在或损坏都返回空表）。
  Future<Map<String, dynamic>> _readRuntimeInfo() async {
    try {
      if (!await paths.runtimeFile.exists()) return const {};
      final decoded = jsonDecode(await paths.runtimeFile.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// 把运行文件写成「我」，从此 `--stop` / `--status` 指向本实例。
  Future<void> _claimRuntimeFile(int port) async {
    try {
      await paths.runtimeFile.writeAsString(
        jsonEncode({
          'pid': pid,
          'port': port,
          'control_token': server.controlToken,
          'version': kServerVersion,
        }),
        flush: true,
      );
      _ownsRuntimeFile = true;
    } catch (e) {
      terminal.log('服务器', '运行文件写入失败（--stop 可能用不了）：$e');
    }
  }

  /// 运行文件里的 PID 已经没了 → 把这份文件接过来（本实例还在跑）。
  Future<void> _takeOverStaleRuntimeFile(int port) async {
    if (_ownsRuntimeFile || _shuttingDown) return;
    final diag = Platform.environment['QS_RUNTIME_WATCH_DIAG'] == '1';
    try {
      final info = await _readRuntimeInfo();
      final recorded = (info['pid'] as num?)?.toInt();
      final alive = recorded == null ? false : _processAlive(recorded);
      if (diag) {
        terminal.log('DIAG', '复查：记录 PID $recorded 存活=$alive');
      }
      if (recorded != null && recorded != pid && alive) return;
      await _claimRuntimeFile(port);
      if (recorded != null && recorded != pid) {
        terminal.log('提示', '原来的实例（PID $recorded）已经不在了，'
            '运行文件已收回本实例（PID $pid）：--stop / --status 现在指向我。');
      }
    } catch (e) {
      if (diag) terminal.log('DIAG', '复查出错：$e');
    }
  }

  /// 这个 PID 还在不在（只查存在性，绝不结束任何进程）。
  ///
  /// 不能只看 `OpenProcess` 成不成功：**进程被结束后，只要还有人持有它的句柄**
  /// （比如启动它的那个程序），进程对象就还在，`OpenProcess` 照样成功 —— 实测就是
  /// 这样：先启动的实例已经被杀掉了，这边却一直当它活着，运行文件永远收不回来。
  /// 所以要再问一次退出码：`STILL_ACTIVE(259)` 才算活着。
  static bool _processAlive(int processId) {
    var handle = 0;
    try {
      handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, processId);
      if (handle == 0) return false;
      final code = calloc<Uint32>();
      try {
        if (GetExitCodeProcess(handle, code) == 0) return true;
        return code.value == 259; // STILL_ACTIVE
      } finally {
        calloc.free(code);
      }
    } catch (_) {
      return true; // 查不了就当它还活着（保守：不乱抢运行文件）
    } finally {
      if (handle != 0) CloseHandle(handle);
    }
  }

  /// 只删自己写的那份运行文件（pid 对得上才删）。
  Future<void> _removeRuntimeFile() async {
    if (!_ownsRuntimeFile) return;
    try {
      if (!await paths.runtimeFile.exists()) return;
      final info = Map<String, dynamic>.from(
          jsonDecode(await paths.runtimeFile.readAsString()) as Map);
      if ((info['pid'] as num?)?.toInt() == pid) {
        await paths.runtimeFile.delete();
      }
    } catch (_) {}
    _ownsRuntimeFile = false;
  }

  /// 已经有一个本程序实例在跑就返回它的 `{port, pid}`，否则 null。
  Future<Map<String, Object?>?> _liveInstance() async {
    final runtime = await findRunningServer(paths);
    if (runtime == null) return null;
    return {'port': runtime['port'], 'pid': runtime['pid']};
  }

  // ------------------------------------------------------------
  // 首次运行：四步引导（一步一介绍，每步都能用数字选）
  // ------------------------------------------------------------

  /// 首次配置：**四步，一步一介绍**。每步先只显示这一步的说明，等用户输入后再进
  /// 下一步（避免一次性糊一整屏）；每步都支持数字快捷选择，也可以直接粘自己的值。
  ///
  /// 没有可交互控制台时（例如用管道跑），把四步的说明整体打一遍，然后提示用
  /// `--api-key` 或直接编辑 config.json —— 看不到提示等于没有提示。
  Future<void> _firstRunSetup() async {
    if (!stdin.hasTerminal) {
      _printSetupGuide();
      terminal.error('当前没有可交互的控制台：请用 --api-key 传入，或直接编辑 '
          '${paths.configFile.path}');
      return;
    }

    terminal.line();
    terminal.line('还没有配置 AI，跟着下面 4 步填一遍就行（每步直接回车 = 用默认值）。');
    terminal.line();

    // ① Provider
    var provider = config.providerId;
    while (true) {
      terminal.line('第 1 步 / 共 4 步 — Provider：接口协议，三选一'
          '（交互输入时直接打 1 / 2 / 3 也行）');
      terminal.line('   1 = openai-compatible  DeepSeek、OpenAI、通义千问(DashScope 兼容)、'
          '智谱、Kimi 等一切 OpenAI 兼容接口');
      terminal.line('   2 = anthropic         Anthropic 官方 Claude 接口');
      terminal.line('   3 = gemini            Google Gemini 官方接口');
      final answer = await _ask(input, '第 1 步·选择 Provider（1/2/3）',
          _providerNumber(provider));
      final picked = _providerFromAnswer(answer);
      if (picked != null) {
        provider = picked;
        break;
      }
      terminal.line('   ？看不懂「$answer」：请输入 1、2、3，或 '
          'openai-compatible / anthropic / gemini。');
      terminal.line();
    }
    terminal.line('   → 已选择：$provider');
    terminal.line();

    // ② Base URL
    var baseUrl = config.baseUrl;
    while (true) {
      terminal.line('第 2 步 / 共 4 步 — Base URL：服务地址（默认使用 DeepSeek，'
          '也可选择 OpenAI 或其他）');
      terminal.line('   1 = DeepSeek  https://api.deepseek.com');
      terminal.line('   2 = OpenAI    https://api.openai.com/v1');
      terminal.line('   也可以直接粘贴自己的地址（不要带 /chat/completions 这种尾巴）。');
      final answer = await _ask(input, '第 2 步·选择服务地址（1/2 或直接粘地址）',
          _urlNumber(baseUrl));
      final picked = _baseUrlFromAnswer(answer);
      if (picked != null) {
        baseUrl = picked;
        break;
      }
      terminal.line('   ？「$answer」看起来不是地址：请输入 1、2，或粘贴 '
          'https:// 开头的完整地址。');
      terminal.line();
    }
    terminal.line('   → 已选择：$baseUrl');
    terminal.line();

    // ③ API Key
    String apiKey;
    while (true) {
      terminal.line('第 3 步 / 共 4 步 — API Key：服务商后台申请的密钥，'
          '形如 sk-xxxxxxxx（只存在这台电脑上）');
      terminal.line('   如 DeepSeek 申请入口：https://platform.deepseek.com/api_keys');
      final answer =
          await _ask(input, '第 3 步·粘贴或输入 API Key（sk-...）', '');
      apiKey = answer.trim();
      if (apiKey.isNotEmpty) break;
      terminal.line('   ？API Key 不能为空：它是调用 AI 的凭证（不是登录密码）。');
      terminal.line('     如果暂时没有，可以先按 Ctrl+C 退出，拿到 Key 后再启动。');
      terminal.line();
    }
    terminal.line('   → 已保存：${_maskKey(apiKey)}');
    terminal.line();

    // ④ Model
    String model;
    while (true) {
      terminal.line('第 4 步 / 共 4 步 — 输入模型名，必须是能看图的多模态模型，'
          '默认为 deepseek-flash');
      terminal.line('   1 = deepseek-flash（默认）   2 = gpt-4o-mini');
      terminal.line('   3 = qwen-vl-max              4 = glm-4v-plus');
      terminal.line('   也可以直接输入别的多模态模型名。');
      final answer = await _ask(input, '第 4 步·选择模型（1/2/3/4 或直接输入模型名）',
          '1');
      final picked = _modelFromAnswer(answer);
      if (picked != null) {
        model = picked;
        break;
      }
      terminal.line('   ？模型名不能为空：直接回车就用默认的 deepseek-flash。');
      terminal.line();
    }
    terminal.line('   → 已选择：$model');
    terminal.line();

    config = config.copyWith(
      providerId: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
    await paths.save(config);
    terminal.line('AI 配置完成，已保存到 ${paths.configFile.path}');
    terminal.line();
  }

  /// 没有交互控制台时，把四步说明整体打一遍（至少让用户知道该填什么）。
  void _printSetupGuide() {
    terminal.line();
    terminal.line('还没有配置 AI。四步分别是：');
    terminal.line('  第 1 步 Provider：1 = openai-compatible（DeepSeek、OpenAI、通义千问、'
        '智谱、Kimi 等一切 OpenAI 兼容接口）');
    terminal.line('                    2 = anthropic（Anthropic 官方 Claude 接口）');
    terminal.line('                    3 = gemini（Google Gemini 官方接口）');
    terminal.line('  第 2 步 Base URL：1 = DeepSeek https://api.deepseek.com'
        '   2 = OpenAI https://api.openai.com/v1   或直接粘自己的地址');
    terminal.line('  第 3 步 API Key：形如 sk-xxxxxxxx（不是登录密码）；'
        'DeepSeek 申请入口 https://platform.deepseek.com/api_keys');
    terminal.line('  第 4 步 Model：必须是能看图的多模态模型，'
        '1 = deepseek-flash（默认） 2 = gpt-4o-mini 3 = qwen-vl-max 4 = glm-4v-plus');
    terminal.line();
  }

  /// 数字选择 → Provider id；看不懂返回 null（让调用方提示重输）。
  static String? _providerFromAnswer(String answer) =>
      switch (answer.trim().toLowerCase()) {
        '1' || 'openai-compatible' || 'openai' || 'deepseek' ||
        'qwen' || 'zhipu' || 'glm' || 'kimi' =>
          'openai-compatible',
        '2' || 'anthropic' || 'claude' => 'anthropic',
        '3' || 'gemini' || 'google' => 'gemini',
        _ => null,
      };

  /// 数字选择 → Base URL；看起来像地址就原样用；否则 null。
  static String? _baseUrlFromAnswer(String answer) {
    final text = answer.trim();
    return switch (text) {
      '1' => 'https://api.deepseek.com',
      '2' => 'https://api.openai.com/v1',
      _ => (text.startsWith('http://') || text.startsWith('https://')) ? text : null,
    };
  }

  /// 数字选择 → 模型名；也可以直接写模型名。
  static String? _modelFromAnswer(String answer) {
    final text = answer.trim();
    if (text.isEmpty) return null;
    return switch (text) {
      '1' => ServerConfig.defaultModel,
      '2' => 'gpt-4o-mini',
      '3' => 'qwen-vl-max',
      '4' => 'glm-4v-plus',
      _ => text,
    };
  }

  static String _urlNumber(String baseUrl) =>
      baseUrl.contains('openai.com') ? '2' : '1';

  /// 只显示头尾，别把整串 Key 打到屏幕上。
  static String _maskKey(String key) => key.length <= 8
      ? '${key.substring(0, 1)}***'
      : '${key.substring(0, 4)}***${key.substring(key.length - 4)}';

  static String _providerNumber(String providerId) => switch (providerId) {
        'anthropic' => '2',
        'gemini' => '3',
        _ => '1',
      };

  Future<String> _ask(LineInput input, String label, String fallback) async {
    terminal.write('$label [${fallback.isEmpty ? '必填' : fallback}]: ');
    final answer = await input.next();
    final text = (answer ?? '').trim();
    terminal.line();
    return text.isEmpty ? fallback : text;
  }

  // ------------------------------------------------------------
  // 热键
  // ------------------------------------------------------------

  /// 每个动作当前**真正注册着**的组合键；null = 没注册上。
  ///
  /// 状态里显示的是真实情况而不是配置里的期望值：注册失败时用户必须一眼看出来
  /// （需求：不能静默失败）。
  final Map<String, String?> _activeHotkeys = {};

  /// 槽位名 → 期望的组合键（两个动作两条键）。
  Map<String, HotkeySpec> _currentSpecs() => {
        HotkeySlot.capture.key: parseHotkey(config.hotkeyCapture),
        HotkeySlot.multipage.key: parseHotkey(config.hotkeyMultipage),
      };

  /// 按槽位名取默认值（配置文件被改坏时回退用）。
  static String defaultHotkeyOf(String slot) => switch (slot) {
        'multipage' => ServerConfig.kDefaultHotkeyMultipage,
        _ => ServerConfig.kDefaultHotkeyCapture,
      };

  /// 槽位名 → 它属于哪个动作（决定按下时执行什么）。
  static HotkeySlot? actionOf(String slot) => switch (slot) {
        'capture' => HotkeySlot.capture,
        'multipage' => HotkeySlot.multipage,
        _ => null,
      };

  Future<void> _setupHotkeys() async {
    final registrar = hotkeys;
    if (registrar == null) return;
    final specs = <String, HotkeySpec>{};
    for (final slot in _currentSpecs().keys) {
      final raw = configValueOf(slot);
      try {
        specs[slot] = parseHotkey(raw);
      } on HotkeyFormatException catch (e) {
        // 配置文件被手工改坏了：退回该槽位的默认值并明确告知，不要静默失败。
        terminal.error('热键「$raw」不可用（${e.message}），已改用默认值 '
            '${defaultHotkeyOf(slot)}');
        specs[slot] = parseHotkey(defaultHotkeyOf(slot));
      }
    }
    await _applyHotkeys(registrar, specs);
  }

  /// 槽位名 → 配置里当前的值。
  String configValueOf(String slot) => switch (slot) {
        'capture' => config.hotkeyCapture,
        'multipage' => config.hotkeyMultipage,
        _ => '',
      };

  Future<void> _applyHotkeys(
    HotkeyRegistrar registrar,
    Map<String, HotkeySpec> specs, {
    Set<String>? only,
  }) async {
    // 只改一条键时**不要**动另外三条：注销 + 重注册全套会平白多出好几次
    // RegisterHotKey/UnregisterHotKey，实测（tool/hotkey_probe.dart）连续操作
    // 偶尔会被系统判成「已被注册」（1409）。改一条只碰一条最稳。
    if (only == null) {
      await registrar.unregister();
    }
    var anyFailed = false;
    for (final entry in specs.entries) {
      final slot = entry.key;
      if (only != null && !only.contains(slot)) continue;
      final spec = entry.value;
      final action = actionOf(slot);
      if (action == null) continue;
      final ok = await registrar.register(
        slot: slot,
        vk: spec.vk,
        nativeModifiers: spec.modifiers,
        onTrigger: () => _onHotkey(action),
      );
      _activeHotkeys[slot] = ok ? spec.label : null;
      if (!ok) {
        anyFailed = true;
        // 需求：不能静默失败，两行固定文案（英文，便于用户搜索/贴给别人）。
        terminal.line('[Hotkey] ${spec.label} registration failed.');
        final code = registrar is HotkeyService ? registrar.lastErrorCode : 0;
        if (code == 1409) {
          terminal.line(
              '[Hotkey] The hotkey may already be used by another application.');
        } else if (code == -1) {
          terminal.line(
              '[Hotkey] The hotkey thread did not respond; please restart the server.');
        } else {
          terminal.line('[Hotkey] RegisterHotKey failed with win32 error $code.');
        }
        terminal.line('[Hotkey] 改用别的键：hotkey $slot <组合键>');
      }
    }
    // 失败之后直接告诉用户「本机还有哪些键可用」，别让他自己一个个试。
    if (anyFailed && registrar is HotkeyService) {
      final free = await registrar.probeFreeFunctionKeys();
      terminal.line(hotkeyFreeKeysHint(free));
    }
  }

  void _onHotkey(HotkeySlot action) {
    switch (action) {
      case HotkeySlot.capture:
        unawaited(flow.onCapture());
      case HotkeySlot.multipage:
        unawaited(flow.onMultipage());
    }
  }

  /// 四个热键彼此不能重复；重复时提示并要求重新输入。
  String? _duplicateCheck(
      Map<String, HotkeySpec> specs, String slot, HotkeySpec candidate) {
    for (final entry in specs.entries) {
      if (entry.key == slot) continue;
      if (entry.value.conflictsWith(candidate)) {
        return '${candidate.label} 与「${_slotTitle(entry.key)}」重复，请换一个';
      }
    }
    return null;
  }

  static String _slotTitle(String slot) => switch (slot) {
        'capture' => '截屏识别',
        'multipage' => '多页模式',
        _ => slot,
      };

  Future<void> _changeHotkey(String slotName, String combo) async {
    final slot = slotName.toLowerCase();
    if (!_currentSpecs().containsKey(slot)) {
      terminal.error('未知热键：$slotName（可用 capture / multipage）');
      return;
    }
    final HotkeySpec spec;
    try {
      spec = parseHotkey(combo);
    } on HotkeyFormatException catch (e) {
      terminal.error(e.message);
      return;
    }
    final specs = _currentSpecs();
    final duplicate = _duplicateCheck(specs, slot, spec);
    if (duplicate != null) {
      terminal.error(duplicate);
      return;
    }
    specs[slot] = spec;
    if (spec.isRiskyBareKey) {
      terminal.log('热键', '注意：${spec.label} 不带修饰键，会把该键的全局输入抢走');
    }
    final registrar = hotkeys;
    if (registrar != null) {
      await _applyHotkeys(registrar, specs, only: {slot});
    } else {
      _activeHotkeys[slot] = spec.label;
    }
    config = config.copyWith(
      hotkeyCapture: specs['capture']!.label,
      hotkeyMultipage: specs['multipage']!.label,
    );
    await paths.save(config);
    terminal.log('热键', '${_slotTitle(slot)} 已改为 ${spec.label}');
    _printStatus();
  }

  Future<void> _resetHotkeys() async {
    final registrar = hotkeys;
    final specs = {
      'capture': parseHotkey(ServerConfig.kDefaultHotkeyCapture),
      'multipage': parseHotkey(ServerConfig.kDefaultHotkeyMultipage),
    };
    if (registrar != null) await _applyHotkeys(registrar, specs);
    config = config.copyWith(
      hotkeyCapture: specs['capture']!.label,
      hotkeyMultipage: specs['multipage']!.label,
    );
    await paths.save(config);
    terminal.log('热键', '热键已恢复默认：截屏识别 ${config.hotkeyCapture} · '
        '多页模式 ${config.hotkeyMultipage}');
    _printStatus();
  }

  // ------------------------------------------------------------
  // 状态 / 二维码 / 中文提示
  // ------------------------------------------------------------

  /// 一个动作的热键文案：真注册上的才显示，没注册上标「未生效」。
  String _actionHotkeyLabel(HotkeySlot action) => hotkeyActionLabel(
        wanted: configValueOf(action.key),
        active: hotkeys == null
            ? configValueOf(action.key)
            : _activeHotkeys[action.key],
      );

  /// 启动标识文案：`第 3 次启动 · 首次 09-23 19:02 · 上次 09-23 20:15`。
  String _runInfoText() {
    final first = store.firstRunAt;
    final last = _previousRunAt;
    final parts = <String>['第 $runIndex 次启动'];
    if (first != null) parts.add('首次 ${_shortTime(first)}');
    parts.add('上次 ${last == null ? '（无）' : _shortTime(last)}');
    return parts.join(' · ');
  }

  static String _shortTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// 上一次印出去的状态内容。用来**去重**：只在内容真的变了才重印。
  ///
  /// 手机断线重连、配对后又握手、WS 心跳超时重连都会触发状态变化；不去重的话
  /// （用户报「连接手机后弹出一堆东西」）屏幕上会刷出一堆一模一样的块。
  String? _lastStatus;

  /// [force] = 用户自己敲了 `status`，这时必须重印（哪怕内容没变）。
  void _printStatus({bool force = false}) {
    final connected = <String>[];
    for (final id in server.connectedDeviceIds) {
      connected.add(store.devices[id]?.info.name ?? id);
    }
    final paired = store.activeDevices
        .where((d) => !server.connectedDeviceIds.contains(d.info.deviceId))
        .map((d) => d.info.name)
        .toList();
    final view = StatusView(
      running: server.port != null,
      ip: lanIp,
      port: server.port,
      pairingCode: server.pairingCode,
      connectedDevices: connected,
      pairedDevices: paired,
      providerLabel: config.providerLabel,
      model: config.model,
      aiConfigured: config.aiConfigured,
      captureLabel: _actionHotkeyLabel(HotkeySlot.capture),
      multipageLabel: _actionHotkeyLabel(HotkeySlot.multipage),
      pendingPages: flow.pendingPages,
      dataDir: paths.dir.path,
      runInfo: _runInfoText(),
    );
    final lines = renderStatusLines(view);
    final fingerprint = lines.join('\n');
    if (!force && fingerprint == _lastStatus) return;
    _lastStatus = fingerprint;
    terminal.line();
    for (final line in lines) {
      terminal.line(line);
    }
  }

  /// 启动完成后的中文提示块（用户第 4 条：热键、配对方法、更多命令都要说清楚）。
  void _printHints() {
    final port = server.port;
    terminal.line();
    terminal.line('怎么用：');
    terminal.line('  1) 手机配对：用手机 App 里的「扫码配对」扫下面的二维码；'
        '扫不出来就手动输入地址与配对码。');
    if (port != null) {
      terminal.line('     地址 $lanIp:$port   配对码 ${server.pairingCode}');
    }
    terminal.line('  2) 截屏识别：按 ${config.hotkeyCapture} → 截取鼠标所在那块屏幕 → '
        '自动识别 → 结果直接推到手机；本机不显示答案。');
    terminal.line('  3) 多页识别：按 ${config.hotkeyMultipage} 进入多页模式并抓第 1 张，'
        '继续按追加，攒满 $kHardMaxPagesPerTask 张会自动上传；没满时按 '
        '${config.hotkeyCapture} 立即结束并上传。');
    terminal.line('  4) 更多命令：help 全部命令 · status 看状态 · qr 看二维码 · '
        'pair 刷新配对码 · hotkey 改热键 · ai 看配置 · devices 已配对手机 · quit 退出。');
    terminal.line('  5) 后台运行：这里输入 hidden → 窗口消失、服务继续跑'
        '（关掉终端也不影响它）；想再看命令行就再打开一次本程序，'
        '停止服务请输入 stop。');
  }

  void _printQr() {
    if (!args.printQr) return;
    final port = server.port;
    if (port == null) return;
    final payload = pairQrPayload(
      host: lanIp,
      port: port,
      code: server.pairingCode,
      serverDeviceId: store.deviceId,
    );
    terminal.line();
    terminal.line('用手机「扫码配对」扫下面这个二维码：');
    terminal.line();
    for (final line in renderQrLines(payload)) {
      terminal.line(line);
    }
    terminal.line();
    terminal.line('扫不出来就手动输入：$lanIp : $port  配对码 ${server.pairingCode}');
    // 安卓端也支持「从剪贴板粘贴配对链接」，所以把链接原文也打出来方便复制。
    terminal.line('也可以把这行配对链接发到手机，在「扫码配对」页粘贴：');
    terminal.line(payload);
  }

  // ------------------------------------------------------------
  // 命令循环
  // ------------------------------------------------------------

  Future<void> _commandLoop() async {
    final stdinLines = input;
    terminal.line();
    terminal.line('命令提示符已就绪（help 看命令，Ctrl+C 或 quit 退出）。');
    while (!_shuttingDown) {
      terminal.write('> ');
      final line = await stdinLines.next();
      if (line == null) break;
      final text = line.trim();
      if (text.isEmpty) continue;
      await _handleCommand(text);
    }
  }

  Future<void> _handleCommand(String text) async {
    final parts = text.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final rest = parts.sublist(1);
    switch (cmd) {
      case 'help':
      case '?':
        terminal.line(kUsage);
      case 'hidden':
      case 'background':
      case 'bg':
        await _goBackground();
      case 'stop':
        terminal.line('正在停止服务…');
        await shutdown(0);
      case 'status':
        _printStatus(force: true);
      case 'qr':
        _printQr();
      case 'pair':
        final code = server.refreshPairingCode();
        terminal.log('手机', '配对码已刷新为 $code');
        _printStatus(force: true);
        _printQr();
      case 'hotkey':
        if (rest.isEmpty) {
          terminal.error('用法：hotkey capture|multipage <组合键>');
          return;
        }
        if (rest.first.toLowerCase() == 'reset') {
          await _resetHotkeys();
          return;
        }
        if (rest.length < 2) {
          terminal.error('用法：hotkey ${rest.first} <组合键>，'
              '例如 hotkey capture F8 或 hotkey multipage Alt+Shift+W');
          return;
        }
        await _changeHotkey(rest.first, rest.sublist(1).join(' '));
      case 'hotkeys':
        if (rest.isNotEmpty && rest.first.toLowerCase() == 'reset') {
          await _resetHotkeys();
        } else {
          terminal.error('用法：hotkeys reset');
        }
      case 'devices':
        if (store.devices.isEmpty) {
          terminal.log('手机', '还没有手机配对过');
        } else {
          for (final d in store.devices.values) {
            terminal.log('手机', '${d.info.name}（${d.info.platform}）'
                '${d.info.isRevoked ? '已吊销' : '已配对'}');
          }
        }
      case 'ai':
        terminal.log('AI', 'Provider：${config.providerLabel}（${config.providerId}）');
        terminal.log('AI', 'Base URL：${config.baseUrl}');
        terminal.log('AI', 'Model：${config.model}');
        terminal.log('AI', 'API Key：${config.apiKey.isEmpty ? '未配置' : '已配置'}');
      case 'set-api-key':
        if (rest.isEmpty) {
          terminal.error('用法：set-api-key <key>');
          return;
        }
        config = config.copyWith(apiKey: rest.first);
        await paths.save(config);
        terminal.log('AI', 'API Key 已保存');
        _printStatus();
      case 'set-model':
        if (rest.isEmpty) {
          terminal.error('用法：set-model <name>');
          return;
        }
        config = config.copyWith(model: rest.first);
        await paths.save(config);
        terminal.log('AI', '模型已改为 ${config.model}');
        _printStatus();
      case 'set-base-url':
        if (rest.isEmpty) {
          terminal.error('用法：set-base-url <url>');
          return;
        }
        config = config.copyWith(baseUrl: rest.first);
        await paths.save(config);
        terminal.log('AI', '服务地址已改为 ${config.baseUrl}');
        _printStatus();
      case 'set-provider':
        if (rest.isEmpty) {
          terminal.error('用法：set-provider openai-compatible|anthropic|gemini');
          return;
        }
        config = config.copyWith(providerId: rest.first);
        await paths.save(config);
        terminal.log('AI', 'Provider 已改为 ${config.providerLabel}');
        _printStatus();
      case 'quit':
      case 'exit':
        await shutdown(0);
      default:
        // 用户很容易把「启动参数」当命令敲进来（他就是这么问的）。
        // 与其回一句「未知命令」，不如直接讲清这两者的区别。
        if (cmd.startsWith('-')) {
          terminal.error('$cmd 是启动参数，不是在窗口里敲的命令。');
          terminal.line('  · 想现在就转后台（窗口消失、服务继续跑）：直接输入 hidden');
          terminal.line('  · 想下次启动就后台运行：在命令行 / 快捷方式里加 --hidden，'
              '想要连窗口都不闪就用 --background');
          terminal.line('  · 停止服务：这里输入 stop，或执行 '
              'QuizSyncAI_Server.exe --stop');
          terminal.line('  · 想看它现在是不是在跑：QuizSyncAI_Server.exe --status');
          terminal.line('  输入 help 可以看到全部窗口内命令。');
          return;
        }
        terminal.error('未知命令：$cmd（输入 help 查看全部命令）');
    }
  }

  /// 把窗口收起来转后台（窗口里的 `hidden` 命令 = 启动参数 `--hidden` 的效果）。
  ///
  /// 走的是**真的脱离控制台**（`FreeConsole`），不是「藏一下窗口」：藏窗口之后进程
  /// 仍然挂在那台控制台上，用户一关终端服务就跟着没了（用户实测反馈的原话）。
  Future<void> _goBackground() async {
    final reason = _backgroundBlockReason();
    if (reason != null) {
      terminal.line('暂时不能转后台：$reason。先完成配置并把手机配对好，'
          '之后启动时加 --hidden 就会自动后台运行。');
      return;
    }
    await _enterBackground();
    // 控制台已经脱离，stdin 也跟着没了 —— 挂在这儿别返回（返回就会走到命令循环收尾，
    // 那等于自己把自己停掉）。
    await _parkForever();
  }

  /// 转到后台运行：脱离控制台 + 日志改由文件承载。
  ///
  /// 顺序是刻意的：先把「以后怎么找回来 / 怎么停」讲清楚并推到控制台，再切掉控制台
  /// 这一路输出，最后才 `FreeConsole()` —— 否则那几句最关键的话会丢在半个死句柄里。
  Future<void> _enterBackground() async {
    terminal.line();
    terminal.line('正在转后台运行，这个窗口马上会消失；服务继续跑，关掉终端也不影响它。');
    terminal.line('  · 想再看命令行：再打开一次 QuizSyncAI_Server.exe'
        '（它会发现后台实例，直接给你一个命令行窗口）');
    terminal.line('  · 停止服务：在那个窗口里敲 stop，或执行 '
        'QuizSyncAI_Server.exe --stop');
    terminal.line('  · 日志文件：${paths.logFile.path}');
    terminal.line('正在脱离控制台（窗口即将消失）…');
    await terminal.flush();

    terminal.detachFromConsole(); // 从此不再往已经要没了的控制台写
    final note = detachConsoleCompletely();
    _detached = true;
    terminal.line();
    terminal.log('后台', note);
    terminal.log('后台', '已在后台运行（PID $pid，端口 ${server.port}）');
    _printStatus(force: true); // 日志文件里留一份现场，事后可查
  }

  /// 转后台的门禁（用内存里的实时状态，比读文件准）：缺什么就返回什么。
  String? _backgroundBlockReason() {
    if (!config.aiConfigured) return '还没有配置 AI';
    if (store.activeDevices.isEmpty) return '还没有配对过任何手机';
    return null;
  }

  /// 挂住不返回：脱离控制台之后没有键盘可读，进程由 stop / --stop 结束
  /// （[shutdown] 里直接 `exit()`，所以这里不需要被唤醒）。
  Future<void> _parkForever() => Completer<void>().future;

  /// 本机命令行转发（`POST /api/v1/console`）的执行口。
  ///
  /// 把这条命令**在这台正在跑的实例上**执行，输出收进内存缓冲返回给请求方 ——
  /// 用户重新打开的那个窗口就是靠它拿到 `status` / `qr` / `hotkey` 这些输出的。
  /// 只接受本机回环 + 控制令牌（校验在 [QuizSyncServer._handleConsole] 里）。
  Future<String> handleRemoteCommand(String command) async {
    final cmd = command.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (cmd == 'stop' || cmd == 'quit' || cmd == 'exit') {
      // 不能在这里直接 shutdown：那会在响应发出去之前就 exit()，窗口只会看到
      // 「连不上后台实例」。先回话，隔一小会儿再停。
      unawaited(Future<void>.delayed(
          const Duration(milliseconds: 250), () => shutdown(0)));
      return '正在停止服务，本窗口即将退出。\n';
    }
    final buffer = StringBuffer();
    final saved = terminal;
    terminal = Terminal.buffer(buffer);
    try {
      await _handleCommand(command);
    } catch (e) {
      buffer.write('[错误] 命令执行失败：$e\n');
    } finally {
      terminal = saved;
    }
    return buffer.toString();
  }

  // ------------------------------------------------------------
  // 退出
  // ------------------------------------------------------------

  Future<void> shutdown(int code) async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    _runtimeWatch?.cancel();
    terminal.line();
    terminal.log('服务器', '正在退出…');
    try {
      await server.stop();
    } catch (_) {}
    try {
      await hotkeys?.dispose();
    } catch (_) {}
    try {
      await store.save();
    } catch (_) {}
    await _removeRuntimeFile();
    terminal.log('服务器', '已退出，再见。');
    terminal.close(); // 关了日志文件句柄再走
    // 显式退出：后台还有一个热键 isolate，不 exit 会有残留进程（需求 13）。
    exit(code);
  }
}

/// 行输入（首次配置问答与命令循环共用同一个 stdin 流）。
class LineInput {
  final StreamIterator<String> _iterator;

  LineInput()
      : _iterator = StreamIterator(
            stdin.transform(utf8.decoder).transform(const LineSplitter()));

  Future<String?> next() async =>
      (await _iterator.moveNext()) ? _iterator.current : null;
}
