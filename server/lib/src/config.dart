import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Server 自己的配置（**只有** AI 四项 + 两个动作的热键 + 端口）。
///
/// 位置：`<exe 所在目录>\QuizSyncAI_Server\config.json`（exe 目录不可写时退回
/// `%APPDATA%`）。这里刻意不读主项目的任何设置：Server 与 Desktop 各自独立，
/// 改了配置互不影响。
class ServerConfig {
  /// 'openai-compatible' | 'anthropic' | 'gemini'
  String providerId;

  /// 空则用 provider 默认地址。
  String baseUrl;
  String apiKey;
  String model;

  /// 监听端口（被占用时从这里开始往后探测 6 个）。
  int port;

  /// 热键：**两个动作各一条键**（用户明确「备用热键功能删除，没用」）。
  ///
  /// - 截屏识别 [hotkeyCapture]（默认 F8）
  /// - 多页模式 [hotkeyMultipage]（默认 F9）
  String hotkeyCapture;
  String hotkeyMultipage;

  ServerConfig({
    this.providerId = defaultProviderId,
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
    this.port = 8765,
    this.hotkeyCapture = kDefaultHotkeyCapture,
    this.hotkeyMultipage = kDefaultHotkeyMultipage,
  });

  // --- 默认值：与主项目「设置 → API 配置」的出厂默认逐字一致 ---------------
  static const String defaultProviderId = 'openai-compatible';
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-flash';

  /// 默认热键（用户点名指定）：**F8 = 截屏识别**、**F9 = 多页模式**。
  ///
  /// 多页模式的行为：第一次按 F9 进入多页并抓第 1 张；继续按追加；攒到 6 张
  /// **自动上传识别**；没满时按 F8 立即结束多页并上传已抓的全部图片。
  static const String kDefaultHotkeyCapture = 'F8';
  static const String kDefaultHotkeyMultipage = 'F9';

  /// 历代默认值（含已作废的备用键、追加/结束等槽位的历史取值）：
  /// 老配置里如果正好是这些，升级时自动换成上面这组新默认。
  static const List<String> kLegacyDefaultHotkeys = [
    'F6', 'F7', 'F8', 'F9', 'F10', 'F11', // 1.0.0 早期的裸 F 键默认
    'Ctrl+F6', 'Shift+F6', // 中间试过的一版
    'Ctrl+Q', 'Ctrl+Shift+A', 'Ctrl+Shift+S', // 上一版的三个动作默认
    'Alt+Shift+Q', 'Alt+Shift+W', // 已删除的备用键
  ];

  bool get aiConfigured => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 老配置 → 新热键方案（只有两条键了）。
  ///
  /// 只要老配置里出现过已作废的槽位（`hotkey_append` / `hotkey_finish` /
  /// `hotkey_capture_fallback` / `hotkey_multipage_fallback`），或者值等于某个历史
  /// 默认值，就把两条键都摆回默认；用户自己改过、且不属于历史默认的值原样保留。
  ServerConfig withMigratedHotkeys() => copyWith(
        hotkeyCapture: kLegacyDefaultHotkeys.contains(hotkeyCapture)
            ? kDefaultHotkeyCapture
            : hotkeyCapture,
        hotkeyMultipage: kLegacyDefaultHotkeys.contains(hotkeyMultipage)
            ? kDefaultHotkeyMultipage
            : hotkeyMultipage,
      );

  /// 老配置里带着已作废的热键槽位（用来提示「热键方案已更新」）。
  static bool hadLegacySlots(Map<String, dynamic> json) =>
      json.containsKey('hotkey_append') ||
      json.containsKey('hotkey_finish') ||
      json.containsKey('hotkey_capture_fallback') ||
      json.containsKey('hotkey_multipage_fallback');

  /// 显示用：Provider 栏的人读名字。
  String get providerLabel => switch (providerId) {
        'anthropic' => 'Anthropic Claude',
        'gemini' => 'Google Gemini',
        _ => 'DeepSeek / OpenAI 兼容',
      };

  Map<String, dynamic> toJson() => {
        'provider': providerId,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'port': port,
        'hotkey_capture': hotkeyCapture,
        'hotkey_multipage': hotkeyMultipage,
      };

  /// 读配置（顺手套用热键迁移：老方案的槽位与历史默认值都会换成新的两条键）。
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    String str(String key, String fallback) {
      final v = json[key]?.toString();
      return (v == null || v.trim().isEmpty) ? fallback : v.trim();
    }

    final base = ServerConfig(
      providerId: str('provider', defaultProviderId),
      baseUrl: str('base_url', defaultBaseUrl),
      apiKey: json['api_key']?.toString() ?? '',
      model: str('model', defaultModel),
      port: (json['port'] as num?)?.toInt() ?? 8765,
      hotkeyCapture: str('hotkey_capture', kDefaultHotkeyCapture),
      hotkeyMultipage: str('hotkey_multipage', kDefaultHotkeyMultipage),
    );
    return base.withMigratedHotkeys();
  }

  ServerConfig copyWith({
    String? providerId,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? port,
    String? hotkeyCapture,
    String? hotkeyMultipage,
  }) =>
      ServerConfig(
        providerId: providerId ?? this.providerId,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        port: port ?? this.port,
        hotkeyCapture: hotkeyCapture ?? this.hotkeyCapture,
        hotkeyMultipage: hotkeyMultipage ?? this.hotkeyMultipage,
      );
}

/// 数据目录：配置 + 状态 + 图片 + 日志。
///
/// 默认放在 **exe 同目录下的应用同名目录**（`…\QuizSyncAI_Server\`），也就是
/// 「程序在哪，数据就在哪」的便携形态：拷走整个文件夹就带走了配对信息与历史。
/// exe 所在目录不可写（装在 Program Files 等）时才退回 `%APPDATA%`，并把实际用到的
/// 路径打日志，绝不让用户猜数据在哪。
class ConfigPaths {
  /// 根目录（默认 `<exe 所在目录>\QuizSyncAI_Server`）。
  final Directory dir;

  /// 是否用了 `%APPDATA%` 兜底（面板/日志里要说明）。
  final bool fallbackToAppData;

  /// 是否是 `--config` 明确指定的目录。
  ///
  /// 明确指定时不搬老数据：调用方（多实例 / 测试 / 想另开一份数据的人）要的是
  /// 「就用这个目录」，把用户 %APPDATA% 里的老数据倒进来是越权。
  final bool explicit;

  ConfigPaths(this.dir, {this.fallbackToAppData = false, this.explicit = false});

  /// 数据目录名 = 应用同名目录。
  static const String dataDirName = 'QuizSyncAI_Server';

  /// exe 所在目录（单测可替换，避免去碰真实的 Dart SDK / 程序目录）。
  static String Function() executableDirProvider =
      () => p.dirname(Platform.resolvedExecutable);

  /// 老版本数据目录（单测可替换）。
  static Directory Function() legacyDirProvider = _defaultLegacyDir;

  static Directory _defaultLegacyDir() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return Directory(p.join(p.dirname(Platform.resolvedExecutable), 'serverdata'));
    }
    return Directory(p.join(appData, 'QuizSyncAI', 'Server'));
  }

  /// 老版本用的是 `%APPDATA%\QuizSyncAI\Server`（1.0.0 早期构建）。
  static Directory get legacyDir => legacyDirProvider();

  /// 允许 `--config <file>` 指定别的目录（便于多实例/测试）。
  factory ConfigPaths.resolve({String? override}) {
    final explicit = override ?? Platform.environment['QUIZSYNC_SERVER_DIR'];
    if (explicit != null && explicit.isNotEmpty) {
      final abs = p.absolute(explicit);
      // `--config <盘符>:\x\config.json` 与 `--config <盘符>:\x` 都接受：是文件就取父目录。
      final d = p.basename(abs).toLowerCase().endsWith('.json')
          ? Directory(p.dirname(abs))
          : Directory(abs);
      return ConfigPaths(d, explicit: true);
    }
    final near = Directory(p.join(executableDirProvider(), dataDirName));
    if (_isWritable(near)) return ConfigPaths(near);

    // exe 同目录不可写（Program Files 之类）：退回 %APPDATA%，并如实告知。
    final legacy = legacyDir;
    final appDataRoot = Platform.environment['APPDATA'];
    final fallback = (appDataRoot != null && appDataRoot.isNotEmpty)
        ? Directory(p.join(appDataRoot, 'QuizSyncAI', dataDirName))
        : legacy;
    return ConfigPaths(fallback, fallbackToAppData: true);
  }

  /// 能不能在这里建目录/写文件（不能就说明该走兜底）。
  static bool _isWritable(Directory d) {
    try {
      if (d.existsSync()) {
        final probe = File(p.join(d.path, '.write-probe'));
        probe.writeAsStringSync('ok', flush: true);
        probe.deleteSync();
        return true;
      }
      d.createSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把早期 `%APPDATA%` 里的数据搬到新目录（只在新目录还没有数据时做一次）。
  ///
  /// 不搬的话，用户升级后会发现「配对没了、历史空了」，而且手机上的 token 也失效，
  /// 得重新扫码 —— 那不是升级该有的样子。
  Future<void> migrateLegacyIfNeeded() async {
    if (fallbackToAppData || explicit) return;
    if (p.equals(dir.path, legacyDir.path)) return;
    try {
      if (await stateFile.exists() || await configFile.exists()) return;
      if (!await legacyDir.exists()) return;
      await ensure();
      await for (final entity in legacyDir.list()) {
        final name = p.basename(entity.path);
        final target = p.join(dir.path, name);
        if (entity is Directory) {
          await _copyDir(entity, Directory(target));
        } else if (entity is File) {
          await entity.copy(target);
        }
      }
    } catch (_) {
      // 迁移失败不影响启动：新目录照样能用，最多是要重新配对一次。
    }
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    if (!await to.exists()) await to.create(recursive: true);
    await for (final entity in from.list()) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDir(entity, Directory(p.join(to.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(to.path, name));
      }
    }
  }

  File get configFile => File(p.join(dir.path, 'config.json'));
  File get stateFile => File(p.join(dir.path, 'state.json'));

  /// 后台（无窗口）模式的日志文件。
  File get logFile => File(p.join(dir.path, 'server.log'));

  /// 运行信息：`{"pid":…,"port":…,"control_token":"…"}`，供 `--stop` 定位本进程。
  File get runtimeFile => File(p.join(dir.path, 'runtime.json'));

  Directory get imageDir => Directory(p.join(dir.path, 'images'));

  Future<void> ensure() async {
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  /// 读配置的**原始 JSON**（文件不存在或损坏时返回 null）。
  ///
  /// 需要它是因为「老配置用的还是三个动作的热键方案」这件事只能从原始键名看出来
  /// —— [ServerConfig.fromJson] 会顺手把老方案迁移掉。
  Future<Map<String, dynamic>?> loadRaw() async {
    try {
      if (!await configFile.exists()) return null;
      final decoded = jsonDecode(await configFile.readAsString());
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 读配置；文件不存在或损坏时返回 null（调用方据此走首次配置流程）。
  Future<ServerConfig?> load() async {
    final raw = await loadRaw();
    return raw == null ? null : ServerConfig.fromJson(raw);
  }

  Future<void> save(ServerConfig config) async {
    await ensure();
    // 先写临时文件再改名：断电/被杀时不会留下半个 JSON 把下次启动卡死。
    final tmp = File('${configFile.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
        flush: true);
    if (await configFile.exists()) await configFile.delete();
    await tmp.rename(configFile.path);
  }
}
