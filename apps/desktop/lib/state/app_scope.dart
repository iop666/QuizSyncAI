import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../services/desktop_server.dart';
import '../services/hotkeys.dart';
import '../services/remote_task.dart';
import 'analysis_workflow.dart';
import 'settings.dart';

/// 手机任务状态信号（M44 第 5 条）：类体在 `services/remote_task.dart`，
/// 这里**再导出**一次，外壳与悬浮窗照旧从本文件 import。
export '../services/remote_task.dart' show RemoteTaskSignal;

/// 由 main() 在启动时 override；widget 测试注入假实现。
final dbProvider = Provider<QuizSyncDb>(
    (ref) => throw UnimplementedError('dbProvider must be overridden'));

final repoProvider = Provider<CoreRepository>((ref) {
  final repo = CoreRepository(db: ref.watch(dbProvider), deviceId: 'windows-local');
  return repo;
});

final settingsProvider =
    ChangeNotifierProvider<SettingsController>((ref) => throw UnimplementedError(
        'settingsProvider must be overridden'));

/// AI provider 注册表（真实实现 + 测试注入 FakeAiProvider）。
final aiProviderRegistryProvider =
    Provider<Map<String, QuizAiProvider>>((ref) => {
          'openai-compatible': OpenAiCompatibleProvider(),
          'anthropic': AnthropicProvider(),
          'gemini': GeminiProvider(),
        });

final workflowProvider = Provider<AnalysisWorkflow>((ref) {
  final repo = ref.watch(repoProvider);
  final registry = ref.watch(aiProviderRegistryProvider);
  final dailyLimit = ref.watch(settingsProvider).ai.dailyLimit;
  final workflow = AnalysisWorkflow(
    repo: repo,
    engine: AnalysisEngine(
      provider: _SwitchableProvider(registry),
      cache: AnalysisCache(repo),
      quota: QuotaGuard(repo.db, dailyLimit: dailyLimit),
      deviceId: 'windows-local',
    ),
    deviceId: 'windows-local',
  );
  // 用户反馈 2：主机自己截屏时，手机端以前什么都不知道（「已连接却看不到新记录」）。
  // 本地任务的开始/结束都广播给已配对的手机，手机端据此显示「N 张图片识别中…」
  // 并在完成后自动加载结果。服务端没起来时静默跳过。
  void notify(String sessionId, String status, int imageCount) {
    try {
      ref
          .read(serverControllerProvider)
          .notifyLocalSession(sessionId, status, imageCount: imageCount);
    } catch (_) {
      // serverControllerProvider 未注入（单测/未启动）：不影响本地识别。
    }
  }

  workflow.onSessionStarted = (sessionId, imageCount) =>
      notify(sessionId, 'analyzing', imageCount);
  workflow.onSessionFinished = (sessionId, ok) =>
      notify(sessionId, ok ? 'done' : 'failed', 0);
  return workflow;
});

/// API Key 的读取器（真实实现走 flutter_secure_storage；测试注入内存版）。
/// 手机（安卓）发起的识别会话（用户反馈 12）。
///
/// 服务端收到手机任务时由外壳写入，主界面据此把右侧切到那次识别。
///
/// M44 第 5 条（用户要求「手机端识别时 Windows 端静默不弹出」）：**不再把窗口
/// 带到前台** —— 只有窗口本来就在前台时才顺手切到识别界面（见 `_onRemoteTaskStarted`）。
final remoteTaskSession = ValueNotifier<String?>(null);

/// 手机任务的**状态信号**（M44 第 5 条）：`queued` / `analyzing` / `done` / `failed`。
///
/// 服务端在 `onTaskUpdateHook` 里写这个值；外壳监听它，转发给悬浮窗 ——
/// 手机在搜题时，悬浮窗要能显示「手机正在识别…」，并且识别完**跳到新结果**
/// （之前悬浮窗完全不知道手机那边发生了什么，用户报「悬浮窗不会同步状态与跳转新界面」）。
///
/// `ValueNotifier` 记的是最后一个值：外壳挂监听时先读一次当前值，错过早期事件也能补上。
final remoteTaskState = ValueNotifier<RemoteTaskSignal?>(null);

/// 悬浮窗外观 / 行为的**指纹**（M32）。
///
/// 与 `ballSignature` 同样的理由（M15 第 1 条）：`settingsProvider` 是
/// `ChangeNotifierProvider`，直接 `listen` 时 `prev/next` 是同一个 controller
/// 实例，前后比较永远相等 —— 必须用 `select` 取出这几个字段的指纹。
String floatWindowSignature(AppSettings app) => [
      app.floatWindowEnabled,
      app.floatWindowTopmost,
      app.floatWindowOpacity,
      app.floatWindowScale,
      app.floatWindowFontScale,
      // M33：外观（三种预设）与配色取代了 M32 的「比例 + 拉伸边界」。
      app.floatWindowAspect,
      app.floatWindowPalette,
      app.floatWindowLocked,
      app.floatWindowTheme.name,
      app.floatWindowMinimal,
      // 位置也要进签名：设置页的「恢复默认位置」只改这两个字段（x/y = -1），
      // 不在这里看着它，窗口就不会被重新摆位。
      app.floatWindowX,
      app.floatWindowY,
      app.accent,
      app.theme.name,
    ].join('|');

/// 两个热键槽位当前设置值的**指纹**（用户反馈 14）。
///
/// 外壳用它判断「热键设置有没有变」：任意一个槽位（截屏识别 / 多页模式）变了就
/// 重新注册全部热键。原来的代码只监听第一个槽位，于是改多页热键完全不会重新注册，
/// 用户以为「设置了没保存」。
String hotkeySettingsSignature(AppSettings app) => [
      app.hotkeyJson ?? '',
      app.multipageHotkeyJson ?? '',
    ].join('|');

/// 悬浮球外观的**指纹**（用户反馈 11；M15 第 1 条修监听方式时抽出来）。
///
/// 只有这些字段变了才需要重画悬浮球窗口。**必须配合 `select` 使用**：
/// `settingsProvider` 是 `ChangeNotifierProvider`，它的值就是 controller 实例本身，
/// 直接 `listen` 整个 provider 时 `prev` 与 `next` 是同一个对象（读到的都是新值），
/// 用它做「前后比较」永远不会成立 —— 这就是「悬浮球大小 / 透明度 / 描边 / 开关
/// 全都调不动」的根因（见 `main.dart` 的监听处与 `settings_listener_test.dart`）。
String ballSignature(AppSettings app) => [
      app.ballEnabled,
      app.ballSize,
      app.ballOpacity,
      app.ballStroke,
      app.ballStrokeWidth,
      app.ballStrokeOpacity,
    ].join('|');

final remoteTaskSessionProvider =
    Provider<ValueNotifier<String?>>((ref) => remoteTaskSession);

final apiKeyReaderProvider =
    Provider<Future<String?> Function()>((ref) => () async => null);

/// API Key 的写入器。
final apiKeyWriterProvider =
    Provider<Future<void> Function(String)>((ref) => (_) async {});

/// 全局热键每个槽位的**真实注册状态**（用户反馈 6：重写热键模块）。
/// 由 `_DesktopShell` 在注册完成后写入；设置页与顶栏都读它，不得写死按键名。
final hotkeyStatusProvider =
    StateProvider<Map<HotkeySlot, HotkeyStatus>>((ref) => const {});

/// 自增一次 = 让 `_DesktopShell` 重新注册全部热键。
///
/// M12 起设置页不再有「重新注册」按钮（用户反馈 10：连点会触发 bug，
/// 改成「恢复默认」）——这个 provider 只留给「需要强制重注册」的入口
/// （例如外部拉起、测试）。
final hotkeyReloadProvider = StateProvider<int>((ref) => 0);

/// 热键设置页现在是不是**挂载着**（用户反馈 5，M31 重新定义语义）。
///
/// 注意它**不再**等于「热键被暂停」：M30 曾用它去 `unregister()` 全部热键，
/// 结果在「页面没被卸载（窗口收进托盘 / 最小化）」时把热键永久锁死。
/// 现在它只是「页面在树上」这一个事实，真正的抑制条件是
/// `挂载 && 本窗口是前台窗口`（`_DesktopShell._hotkeyBlocked()`），
/// 判断发生在**触发那一刻**，注册始终有效。
///
/// 不抑制的话，在热键页里按一下组合键（尤其是想试试某个键能不能用）
/// 就会真的触发一次截屏识别，用户观感就是「设置热键时也在截屏」。
final hotkeysSuspendedProvider = StateProvider<bool>((ref) => false);

String? _activeLabelOf(Ref ref, HotkeySlot slot) =>
    ref.watch(hotkeyStatusProvider)[slot]?.activeLabel;

/// 实际生效的截屏识别热键标签（null = 候选键全被其他程序占用）。
final activeHotkeyProvider =
    Provider<String?>((ref) => _activeLabelOf(ref, HotkeySlot.capture));

/// 实际生效的多页模式热键标签（M46 第 1 条：多页只有一个键）。
final activeMultipageHotkeyProvider =
    Provider<String?>((ref) => _activeLabelOf(ref, HotkeySlot.multipage));

/// 桌面内置服务端控制器（main 注入）。
final serverControllerProvider = Provider<DesktopServerController>(
    (ref) => throw UnimplementedError(
        'serverControllerProvider must be overridden'));

/// 「连接设备」开关的**真正启停**（M32 用户需求 3；main 注入）。
///
/// 服务端启动需要 `imageDir` / provider 注册表 / Key 读取器，这些都只有 `main()`
/// 里才有，所以设置页只负责改设置值，启停动作交给这里。测试里默认 no-op。
final connectToggleProvider =
    Provider<Future<void> Function(bool)>((ref) => (_) async {});

/// 按 providerId 动态分发的包装。
class _SwitchableProvider extends QuizAiProvider {
  final Map<String, QuizAiProvider> registry;
  String activeId = 'openai-compatible';

  _SwitchableProvider(this.registry);

  @override
  String get id => activeId;

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) {
    final provider = registry[config.providerId] ?? registry.values.first;
    activeId = provider.id;
    return provider.analyze(
        jpegBytesList: jpegBytesList, prompt: prompt, config: config);
  }
}

/// 会话列表（时间倒序、排除 tombstone）。
/// 只看某个合集时用 `collectionSessionsProvider(id)`（state/collections.dart）。
final sessionsProvider = StreamProvider<List<Session>>((ref) {
  return ref.watch(repoProvider).watchSessions();
});

/// 指定会话的题目。
final questionsProvider =
    FutureProvider.family.autoDispose<List<Question>, String>((ref, sessionId) {
  return ref.watch(repoProvider).questionsOfSession(sessionId);
});

/// 今日 AI 用量。autoDispose：设置页每次打开重新读，避免长期显示旧数字
/// （原来非 autoDispose、也没有任何地方 invalidate，分析完成后数字永远是旧的）。
final usageTodayProvider = FutureProvider.autoDispose<int>((ref) {
  return QuotaGuard(ref.watch(repoProvider).db).usedToday();
});
