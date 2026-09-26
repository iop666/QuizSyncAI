import 'package:flutter/foundation.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 两端共享的应用设置（原 desktop state/settings.dart 上移，安卓复用）。

/// 键值存储抽象：真实实现走 DB settings 表；测试用内存实现。
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _map = {};
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}

class DriftKeyValueStore implements KeyValueStore {
  final CoreRepository repo;
  DriftKeyValueStore(this.repo);
  @override
  Future<String?> read(String key) => repo.getSetting(key);
  @override
  Future<void> write(String key, String value) => repo.setSetting(key, value);
}

enum ThemeMode2 { system, light, dark }

/// Windows 悬浮窗的明暗模式（M32 用户需求 1.11）：默认跟随软件设置。
enum FloatWindowTheme {
  followApp('跟随软件设置'),
  light('明亮'),
  dark('深色');

  const FloatWindowTheme(this.label);

  final String label;
}

/// 应用外观与行为设置（SPEC 2.3 / 4.1 / 4.2）。两端各自独立持久化。
class AppSettings {
  final ThemeMode2 theme;
  final double fontSize; // 12–32，默认 16
  final bool clipboardWatch; // 默认开
  final bool saveImageFiles; // 是否保存图片文件到本地
  final int listenPort; // 默认 8765（M4 生效）

  /// 自定义全局热键（HotKey.toJson）；null = 用默认候选键自动探测。
  ///
  /// [hotkeyJson] 是「截屏识别」、[multipageHotkeyJson] 是「多页模式」（M46 第 1 条：
  /// 热键只留两个，默认 F8 / F9）。落库键名沿用 `hotkey_json` 与
  /// `hotkey_json_append`，**老库里用户设过的「添加页面」键自动变成新的多页热键**；
  /// 原来的 `hotkey_json_finish`（结束多页识别）不再读取也不写入 —— 那条热键已经
  /// 并进「截屏识别」，留着它只会让老配置把一个不存在的动作注册成全局热键。
  final String? hotkeyJson;
  final String? multipageHotkeyJson;

  final int accent; // 主题种子色（ARGB），默认品牌绿 #16A34A

  /// 本地截取图片缓存上限（用户需求 5）：默认 60 张，0 = 不设限。
  final int imageCacheLimit;

  /// 多页识别单次最多页数（用户需求 4）：默认 6，范围 1..12。
  final int multiPageLimit;

  /// 题目正文字重（用户反馈 1）：MiSans 可变字体的 wght 轴，默认 400。
  final int questionFontWeight;

  /// 界面整体缩放（用户反馈 9）：0.5–3.0，默认 1.0。
  final double uiScale;

  /// 安卓「识别模块」（截取图片传主机分析）总开关（用户需求 11）：默认关闭。
  final bool androidRecognitionEnabled;

  /// Windows 悬浮球（用户反馈 11）：开关、大小、透明度、描边。
  final bool ballEnabled;
  final double ballSize;
  final double ballOpacity;
  final bool ballStroke;
  final double ballStrokeWidth;
  final double ballStrokeOpacity;

  /// Windows 悬浮窗（M32 用户需求 1）：一个贴在桌面上的小窗，实时显示最近一次
  /// 识别结果，并直接在窗内完成「识别 / 多页识别 / 重新识别 / 翻记录」。
  ///
  /// [floatWindowScale] 是**宽度倍率**，[floatWindowAspect] 是三选一的外观
  /// （自带宽高比与基准宽度），两者一起决定窗口的逻辑尺寸（见
  /// [floatWindowWidthLogical] / [floatWindowHeightLogical]）。
  final bool floatWindowEnabled;
  final bool floatWindowTopmost;
  final double floatWindowOpacity;
  final double floatWindowScale;
  final double floatWindowFontScale;

  /// 外观 id（[kFloatWindowAspects] 里的 id）——M33 第 15 条：只有三种，
  /// 不再支持自由拉伸。
  final String floatWindowAspect;

  /// 配色 id（[kFloatWindowPalettes] 里的 id）——M33 第 9 条，默认浅色系。
  final String floatWindowPalette;

  final bool floatWindowLocked;
  final FloatWindowTheme floatWindowTheme;
  final bool floatWindowMinimal;

  /// 窗口位置（逻辑像素）；[kFloatWindowNoPosition] = 还没摆过 → 用默认位置。
  final double floatWindowX;
  final double floatWindowY;

  /// Windows「连接设备」总开关（M32 用户需求 3）：**默认关闭**。
  /// 关着时不启动内置服务端（不监听端口）；打开时才启动并申请网络权限。
  final bool connectEnabled;

  const AppSettings({
    this.theme = ThemeMode2.system,
    this.fontSize = 16,
    this.clipboardWatch = true,
    this.saveImageFiles = true,
    this.listenPort = 8765,
    this.hotkeyJson,
    this.multipageHotkeyJson,
    this.accent = 0xFF16A34A,
    this.imageCacheLimit = kDefaultImageCacheLimit,
    this.multiPageLimit = kDefaultMultiPageLimit,
    this.androidRecognitionEnabled = false,
    this.questionFontWeight = 400,
    this.uiScale = 1.0,
    // 用户反馈 M14 第 4 条：悬浮球默认打开（用户明确要求「默认打开悬浮球」）。
    this.ballEnabled = kDefaultBallEnabled,
    this.ballSize = kDefaultBallSize,
    this.ballOpacity = kDefaultBallOpacity,
    // M17 第 1 条：描边默认打开、宽 4、不透明度 25%。
    this.ballStroke = kDefaultBallStroke,
    this.ballStrokeWidth = kDefaultBallStrokeWidth,
    this.ballStrokeOpacity = kDefaultBallStrokeOpacity,
    // M32：悬浮窗默认关闭，其余按需求里的默认值。
    this.floatWindowEnabled = kDefaultFloatWindowEnabled,
    this.floatWindowTopmost = kDefaultFloatWindowTopmost,
    this.floatWindowOpacity = kDefaultFloatWindowOpacity,
    this.floatWindowScale = kDefaultFloatWindowScale,
    this.floatWindowFontScale = kDefaultFloatWindowFontScale,
    this.floatWindowAspect = kDefaultFloatWindowAspect,
    this.floatWindowPalette = kDefaultFloatWindowPalette,
    this.floatWindowLocked = kDefaultFloatWindowLocked,
    this.floatWindowTheme = FloatWindowTheme.followApp,
    this.floatWindowMinimal = kDefaultFloatWindowMinimal,
    this.floatWindowX = kFloatWindowNoPosition,
    this.floatWindowY = kFloatWindowNoPosition,
    this.connectEnabled = kDefaultConnectEnabled,
  });

  /// 悬浮窗的逻辑宽度 / 高度（未乘 DPI）。
  /// 当前外观（未知 id 时回退到默认的竖屏 9:20）。
  FloatWindowAspect get floatWindowAspectSpec =>
      floatWindowAspectOf(floatWindowAspect);

  double get _fwScale =>
      floatWindowScale.clamp(kMinFloatWindowScale, kMaxFloatWindowScale);

  double get floatWindowWidthLogical =>
      floatWindowAspectSpec.widthAt(_fwScale);

  double get floatWindowHeightLogical =>
      floatWindowAspectSpec.heightAt(_fwScale);

  AppSettings copyWith({
    ThemeMode2? theme,
    double? fontSize,
    bool? clipboardWatch,
    bool? saveImageFiles,
    int? listenPort,
    String? hotkeyJson,
    bool clearHotkey = false,
    String? multipageHotkeyJson,
    bool clearMultipageHotkey = false,
    int? accent,
    int? imageCacheLimit,
    int? multiPageLimit,
    bool? androidRecognitionEnabled,
    int? questionFontWeight,
    double? uiScale,
    bool? ballEnabled,
    double? ballSize,
    double? ballOpacity,
    bool? ballStroke,
    double? ballStrokeWidth,
    double? ballStrokeOpacity,
    bool? floatWindowEnabled,
    bool? floatWindowTopmost,
    double? floatWindowOpacity,
    double? floatWindowScale,
    double? floatWindowFontScale,
    String? floatWindowAspect,
    String? floatWindowPalette,
    bool? floatWindowLocked,
    FloatWindowTheme? floatWindowTheme,
    bool? floatWindowMinimal,
    double? floatWindowX,
    double? floatWindowY,
    bool? connectEnabled,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        fontSize: (fontSize ?? this.fontSize).clamp(12.0, 32.0),
        clipboardWatch: clipboardWatch ?? this.clipboardWatch,
        saveImageFiles: saveImageFiles ?? this.saveImageFiles,
        listenPort: listenPort ?? this.listenPort,
        hotkeyJson: clearHotkey ? null : (hotkeyJson ?? this.hotkeyJson),
        multipageHotkeyJson: clearMultipageHotkey
            ? null
            : (multipageHotkeyJson ?? this.multipageHotkeyJson),
        accent: accent ?? this.accent,
        imageCacheLimit:
            (imageCacheLimit ?? this.imageCacheLimit) < 0 ? 0 : (imageCacheLimit ?? this.imageCacheLimit),
        multiPageLimit:
            (multiPageLimit ?? this.multiPageLimit).clamp(1, kHardMaxPagesPerTask),
        androidRecognitionEnabled:
            androidRecognitionEnabled ?? this.androidRecognitionEnabled,
        questionFontWeight: (questionFontWeight ?? this.questionFontWeight)
            .clamp(kMinQuestionFontWeight, kMaxQuestionFontWeight),
        uiScale: (uiScale ?? this.uiScale).clamp(kMinUiScale, kMaxUiScale),
        ballEnabled: ballEnabled ?? this.ballEnabled,
        ballSize:
            (ballSize ?? this.ballSize).clamp(kMinBallSize, kMaxBallSize),
        ballOpacity: (ballOpacity ?? this.ballOpacity)
            .clamp(kMinBallOpacity, 1.0),
        ballStroke: ballStroke ?? this.ballStroke,
        ballStrokeWidth: (ballStrokeWidth ?? this.ballStrokeWidth)
            .clamp(kMinBallStrokeWidth, kMaxBallStrokeWidth),
        ballStrokeOpacity: (ballStrokeOpacity ?? this.ballStrokeOpacity)
            .clamp(0.0, 1.0),
        floatWindowEnabled: floatWindowEnabled ?? this.floatWindowEnabled,
        floatWindowTopmost: floatWindowTopmost ?? this.floatWindowTopmost,
        floatWindowOpacity: (floatWindowOpacity ?? this.floatWindowOpacity)
            .clamp(kMinFloatWindowOpacity, 1.0),
        floatWindowScale: (floatWindowScale ?? this.floatWindowScale)
            .clamp(kMinFloatWindowScale, kMaxFloatWindowScale),
        floatWindowFontScale:
            (floatWindowFontScale ?? this.floatWindowFontScale)
                .clamp(kMinFloatWindowFontScale, kMaxFloatWindowFontScale),
        floatWindowAspect:
            floatWindowAspectOf(floatWindowAspect ?? this.floatWindowAspect).id,
        floatWindowPalette:
            floatWindowPaletteOf(floatWindowPalette ?? this.floatWindowPalette).id,
        floatWindowLocked: floatWindowLocked ?? this.floatWindowLocked,
        floatWindowTheme: floatWindowTheme ?? this.floatWindowTheme,
        floatWindowMinimal: floatWindowMinimal ?? this.floatWindowMinimal,
        floatWindowX: floatWindowX ?? this.floatWindowX,
        floatWindowY: floatWindowY ?? this.floatWindowY,
        connectEnabled: connectEnabled ?? this.connectEnabled,
      );

  Map<String, String> toMap() => {
        'theme': theme.name,
        'font_size': fontSize.toString(),
        'clipboard_watch': clipboardWatch ? '1' : '0',
        'save_image_files': saveImageFiles ? '1' : '0',
        'listen_port': listenPort.toString(),
        'hotkey_json': hotkeyJson ?? '',
        'hotkey_json_append': multipageHotkeyJson ?? '',
        'accent': accent.toString(),
        kImageCacheLimitKey: imageCacheLimit.toString(),
        kMultiPageLimitKey: multiPageLimit.toString(),
        kAndroidRecognitionEnabledKey: androidRecognitionEnabled ? '1' : '0',
        kQuestionFontWeightKey: questionFontWeight.toString(),
        kUiScaleKey: uiScale.toString(),
        kBallEnabledKey: ballEnabled ? '1' : '0',
        kBallSizeKey: ballSize.toString(),
        kBallOpacityKey: ballOpacity.toString(),
        kBallStrokeKey: ballStroke ? '1' : '0',
        kBallStrokeWidthKey: ballStrokeWidth.toString(),
        kBallStrokeOpacityKey: ballStrokeOpacity.toString(),
        kFloatWindowEnabledKey: floatWindowEnabled ? '1' : '0',
        kFloatWindowTopmostKey: floatWindowTopmost ? '1' : '0',
        kFloatWindowOpacityKey: floatWindowOpacity.toString(),
        kFloatWindowScaleKey: floatWindowScale.toString(),
        kFloatWindowFontScaleKey: floatWindowFontScale.toString(),
        kFloatWindowAspectKey: floatWindowAspect,
        kFloatWindowPaletteKey: floatWindowPalette,
        kFloatWindowLockedKey: floatWindowLocked ? '1' : '0',
        kFloatWindowThemeKey: floatWindowTheme.name,
        kFloatWindowMinimalKey: floatWindowMinimal ? '1' : '0',
        kFloatWindowXKey: floatWindowX.toString(),
        kFloatWindowYKey: floatWindowY.toString(),
        kConnectEnabledKey: connectEnabled ? '1' : '0',
      };

  factory AppSettings.fromMap(Map<String, String> map) {
    final cache = int.tryParse(map[kImageCacheLimitKey] ?? '');
    final pages = int.tryParse(map[kMultiPageLimitKey] ?? '');
    final weight = int.tryParse(map[kQuestionFontWeightKey] ?? '');
    final scale = double.tryParse(map[kUiScaleKey] ?? '');
    final ballSize = double.tryParse(map[kBallSizeKey] ?? '');
    final ballOpacity = double.tryParse(map[kBallOpacityKey] ?? '');
    final strokeWidth = double.tryParse(map[kBallStrokeWidthKey] ?? '');
    final strokeOpacity = double.tryParse(map[kBallStrokeOpacityKey] ?? '');
    final fwOpacity = double.tryParse(map[kFloatWindowOpacityKey] ?? '');
    final fwScale = double.tryParse(map[kFloatWindowScaleKey] ?? '');
    final fwFont = double.tryParse(map[kFloatWindowFontScaleKey] ?? '');
    // M33：外观只有三种（由 `float_window_aspect` 决定）。M32 存的
    // `float_window_ratio` / `float_window_stretch` **不再读取** —— 用户这一轮
    // 明确要求「默认改为竖屏 9:20、删掉自由拉伸」，留着老比例会让老用户
    // 永远停在横向（实测就是这个问题：旧库 ratio=2.22 但用户要竖屏；而且
    // 那个键已经不在 `toMap()` 里，读也读不到，纯属死代码）。
    final fwAspect = (map[kFloatWindowAspectKey] ?? '').isNotEmpty
        ? map[kFloatWindowAspectKey]
        : kDefaultFloatWindowAspect;
    final fwX = double.tryParse(map[kFloatWindowXKey] ?? '');
    final fwY = double.tryParse(map[kFloatWindowYKey] ?? '');
    String? blank(String? v) => (v == null || v.isEmpty) ? null : v;
    return AppSettings(
      theme: ThemeMode2.values.firstWhere(
        (t) => t.name == map['theme'],
        orElse: () => ThemeMode2.system,
      ),
      fontSize: double.tryParse(map['font_size'] ?? '') ?? 16,
      clipboardWatch: map['clipboard_watch'] != '0',
      saveImageFiles: map['save_image_files'] != '0',
      listenPort: int.tryParse(map['listen_port'] ?? '') ?? 8765,
      hotkeyJson: blank(map['hotkey_json']),
      multipageHotkeyJson: blank(map['hotkey_json_append']),
      accent: int.tryParse(map['accent'] ?? '') ?? 0xFF16A34A,
      imageCacheLimit:
          cache == null || cache < 0 ? kDefaultImageCacheLimit : cache,
      multiPageLimit: (pages ?? kDefaultMultiPageLimit)
          .clamp(1, kHardMaxPagesPerTask),
      androidRecognitionEnabled: map[kAndroidRecognitionEnabledKey] == '1',
      questionFontWeight: (weight ?? kDefaultQuestionFontWeight)
          .clamp(kMinQuestionFontWeight, kMaxQuestionFontWeight),
      uiScale: (scale ?? 1.0).clamp(kMinUiScale, kMaxUiScale),
      // 布尔项用常量默认值：**不能写成 `map[key] == '1'`** —— 键不存在时那是
      // false，会把构造函数的默认值整个绕过去（M14 第 4 条实测：默认打开悬浮球
      // 之后，全新装的机器上悬浮球依然不显示，日志里连一条 `ball` 都没有，
      // 因为读设置时 ballEnabled 恒为 false）。
      ballEnabled: map[kBallEnabledKey] == null
          ? kDefaultBallEnabled
          : map[kBallEnabledKey] == '1',
      ballSize: (ballSize ?? kDefaultBallSize).clamp(kMinBallSize, kMaxBallSize),
      ballOpacity:
          (ballOpacity ?? kDefaultBallOpacity).clamp(kMinBallOpacity, 1.0),
      ballStroke: map[kBallStrokeKey] == null
          ? kDefaultBallStroke
          : map[kBallStrokeKey] == '1',
      ballStrokeWidth: (strokeWidth ?? kDefaultBallStrokeWidth)
          .clamp(kMinBallStrokeWidth, kMaxBallStrokeWidth),
      ballStrokeOpacity:
          (strokeOpacity ?? kDefaultBallStrokeOpacity).clamp(0.0, 1.0),
      // M32：同样用常量默认值兜底（悬浮窗**默认关闭**，键不存在时必须是 false
      // 而不是被 `== '1'` 判成 false —— 这两者在这里恰好一致，但布尔项一律
      // 走「键为 null → 常量默认值」这条统一写法，避免以后改默认值时漏改）。
      floatWindowEnabled: map[kFloatWindowEnabledKey] == null
          ? kDefaultFloatWindowEnabled
          : map[kFloatWindowEnabledKey] == '1',
      floatWindowTopmost: map[kFloatWindowTopmostKey] == null
          ? kDefaultFloatWindowTopmost
          : map[kFloatWindowTopmostKey] == '1',
      floatWindowOpacity: (fwOpacity ?? kDefaultFloatWindowOpacity)
          .clamp(kMinFloatWindowOpacity, 1.0),
      floatWindowScale: (fwScale ?? kDefaultFloatWindowScale)
          .clamp(kMinFloatWindowScale, kMaxFloatWindowScale),
      floatWindowFontScale: (fwFont ?? kDefaultFloatWindowFontScale)
          .clamp(kMinFloatWindowFontScale, kMaxFloatWindowFontScale),
      floatWindowAspect: floatWindowAspectOf(fwAspect).id,
      floatWindowPalette: floatWindowPaletteOf(map[kFloatWindowPaletteKey]).id,
      floatWindowLocked: map[kFloatWindowLockedKey] == null
          ? kDefaultFloatWindowLocked
          : map[kFloatWindowLockedKey] == '1',
      floatWindowTheme: FloatWindowTheme.values.firstWhere(
        (t) => t.name == map[kFloatWindowThemeKey],
        orElse: () => FloatWindowTheme.followApp,
      ),
      floatWindowMinimal: map[kFloatWindowMinimalKey] == null
          ? kDefaultFloatWindowMinimal
          : map[kFloatWindowMinimalKey] == '1',
      floatWindowX: fwX ?? kFloatWindowNoPosition,
      floatWindowY: fwY ?? kFloatWindowNoPosition,
      connectEnabled: map[kConnectEnabledKey] == null
          ? kDefaultConnectEnabled
          : map[kConnectEnabledKey] == '1',
    );
  }
}

/// 题目正文字重可选档位（用户反馈 1）：MiSans 是可变字体，直接给 wght 轴。
const List<int> kQuestionFontWeights = [300, 400, 500, 600, 700];
const int kMinQuestionFontWeight = 200;
const int kMaxQuestionFontWeight = 800;
const int kDefaultQuestionFontWeight = 500;

/// 界面缩放（用户反馈 9）：50%–300%。
const double kMinUiScale = 0.5;
const double kMaxUiScale = 3.0;
const double kDefaultUiScale = 1.0;

/// 界面上可选的缩放档位（用户反馈 7：只给这些固定选项，25% 一档）。
/// 数值都是 0.5 的整数倍，避免浮点误差导致 `DropdownButton` 匹配不上。
const List<double> kUiScalePresets = [
  0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0,
];

/// 悬浮球默认开关。
///
/// 构造函数与 [`AppSettings.fromMap`] **都要用它**：`fromMap` 里曾经写成
/// `map[kBallEnabledKey] == '1'`，键不存在时得到 false，把这里的默认值绕过去 ——
/// 表现就是「默认打开悬浮球」这个要求怎么改都不生效。
///
/// M44 第 3 条（用户要求）：**默认改成关闭**（和悬浮窗一样，装完不主动占屏幕）。
/// 值与 `kDefaultBallEnabled`（core `util/keys.dart`）保持一致，改一处要一起改；
/// 老库里的 `ball_enabled=1` 由 `SettingsController.load()` 一次性迁移。
const bool kDefaultBallEnabled = false;

/// 数值 → 最接近的档位（老配置里存了 1.3 这种非档位值时用）。
double nearestUiScalePreset(double value) {
  var best = kUiScalePresets.first;
  var bestDelta = (value - best).abs();
  for (final p in kUiScalePresets) {
    final d = (value - p).abs();
    if (d < bestDelta) {
      best = p;
      bestDelta = d;
    }
  }
  return best;
}

/// AI 配置中**不入安全存储**的部分（API Key 单独走 flutter_secure_storage）。
///
/// 用户反馈 8：默认就填好 DeepSeek 的多模态模型与地址，用户只要粘一个 API Key
/// 就能用（`deepseek-flash` 支持图片输入，base_url 走 OpenAI 兼容的
/// `/chat/completions`）。
class AiUiSettings {
  /// DeepSeek 默认模型（支持图片输入的多模态模型）。
  static const defaultModel = 'deepseek-flash';

  /// DeepSeek 默认 base_url（本项目会拼成 `{baseUrl}/chat/completions`）。
  static const defaultBaseUrl = 'https://api.deepseek.com';

  final String providerId;
  final String model;
  final String baseUrl;
  final int timeoutSeconds;
  final int dailyLimit;

  const AiUiSettings({
    this.providerId = 'openai-compatible',
    this.model = defaultModel,
    this.baseUrl = defaultBaseUrl,
    this.timeoutSeconds = 90,
    this.dailyLimit = 200,
  });

  AiUiSettings copyWith({
    String? providerId,
    String? model,
    String? baseUrl,
    int? timeoutSeconds,
    int? dailyLimit,
  }) =>
      AiUiSettings(
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        dailyLimit: dailyLimit ?? this.dailyLimit,
      );

  Map<String, String> toMap() => {
        'ai_provider': providerId,
        'ai_model': model,
        'ai_base_url': baseUrl,
        'ai_timeout': timeoutSeconds.toString(),
        'ai_daily_limit': dailyLimit.toString(),
      };

  factory AiUiSettings.fromMap(Map<String, String> map) => AiUiSettings(
        providerId: map['ai_provider'] ?? 'openai-compatible',
        model: _nonBlank(map['ai_model']) ?? defaultModel,
        baseUrl: _nonBlank(map['ai_base_url']) ?? defaultBaseUrl,
        timeoutSeconds: int.tryParse(map['ai_timeout'] ?? '') ?? 90,
        dailyLimit: int.tryParse(map['ai_daily_limit'] ?? '') ?? 200,
      );
}

/// 空串 = 用户从没设置过（沿用默认值），不是「显式清空」。
String? _nonBlank(String? v) => (v == null || v.trim().isEmpty) ? null : v;

/// 设置控制器：加载 / 持久化 / 变更通知。
class SettingsController extends ChangeNotifier {
  final KeyValueStore store;

  AppSettings app = const AppSettings();
  AiUiSettings ai = const AiUiSettings();

  /// 隐私告知是否已确认（首次启动弹窗的依据）。
  bool privacyAcknowledged = false;

  SettingsController(this.store);

  Future<void> load() async {
    final map = <String, String>{};
    for (final key in [
      ...AppSettings.fromMap(const {}).toMap().keys,
      ...AiUiSettings.fromMap(const {}).toMap().keys,
      'privacy_ack',
    ]) {
      final v = await store.read(key);
      if (v != null) map[key] = v;
    }
    // M43（用户要求「把极简模式改成悬浮窗默认显示的模式」）：老库里存着
    // `float_window_minimal=0`（那时出厂值就是 0，绝大多数人从没手动选过），
    // 只改常量默认值救不了他们。这里做**一次性**迁移：没见过标记就把显示模式
    // 摆到新默认值并写下标记；之后用户自己的切换一律以库里的值为准。
    if (await store.read(kFloatWindowModeMigratedKey) != '1') {
      final mode = kDefaultFloatWindowMinimal ? '1' : '0';
      map[kFloatWindowMinimalKey] = mode;
      await store.write(kFloatWindowMinimalKey, mode);
      await store.write(kFloatWindowModeMigratedKey, '1');
    }
    // M44 第 3 条（用户要求「悬浮球默认也关闭」）：同理做一次性迁移 ——
    // 老库里存着 `ball_enabled=1`（那时的出厂值就是开），不改的话已装用户升级后
    // 悬浮球照样在屏幕上；之后用户自己开关的状态以库里的值为准。
    if (await store.read(kBallEnabledMigratedKey) != '1') {
      final ball = kDefaultBallEnabled ? '1' : '0';
      map[kBallEnabledKey] = ball;
      await store.write(kBallEnabledKey, ball);
      await store.write(kBallEnabledMigratedKey, '1');
    }
    app = AppSettings.fromMap(map);
    ai = AiUiSettings.fromMap(map);
    privacyAcknowledged = (map['privacy_ack'] ?? '0') == '1';
    // 迁移写完之后记下「库里已经是什么」，后续 updateApp 只写变化过的键。
    _persisted = Map<String, String>.from(map);
    notifyListeners();
  }

  Future<void> updateApp(AppSettings settings) async {
    app = settings;
    // M47：只写**变化过**的键。设置对象有 32 个字段，原来每动一个开关都要把
    // 32 条键依次写一遍磁盘（还都是 await 串行的）。
    await _writeChanged(settings.toMap());
    notifyListeners();
  }

  Future<void> updateAi(AiUiSettings settings) async {
    ai = settings;
    await _writeChanged(settings.toMap());
    notifyListeners();
  }

  /// 上一次写进存储的键值；只有值真的变了才写（见 [updateApp]）。
  Map<String, String> _persisted = {};

  Future<void> _writeChanged(Map<String, String> map) async {
    for (final e in map.entries) {
      if (_persisted[e.key] == e.value) continue;
      await store.write(e.key, e.value);
      _persisted[e.key] = e.value;
    }
  }

  Future<void> acknowledgePrivacy() async {
    privacyAcknowledged = true;
    await store.write('privacy_ack', '1');
    _persisted['privacy_ack'] = '1';
    notifyListeners();
  }

  /// Ctrl+滚轮 / 双指捏合缩放。
  Future<void> adjustFontSize(double delta) =>
      updateApp(app.copyWith(fontSize: (app.fontSize + delta).clamp(12, 32)));
}
