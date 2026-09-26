import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quizsync_ui/quizsync_ui.dart'
    show QuizSyncTheme, ThemeMode2;

import 'state/app_info.dart';
import 'state/app_state.dart';
import 'state/providers.dart';
import 'ui/home_page.dart';
import 'ui/pairing_page.dart';
import 'ui/system_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式系统栏（用户需求 4）：内容铺到状态栏/导航栏底下，再由
  // [ThemedSystemUi] 按主题给出「透明底 + 图标明暗」样式。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // M24：配对 token 的存储换成 AndroidX Security 的 EncryptedSharedPreferences
  // （9.x 的默认值是 false，走旧的「Keystore 包裹 AES + 普通 prefs」实现）。
  // 两种实现落在**不同的 prefs 文件**里，因此升级后旧 token 读不出来 = 需要重新配对一次；
  // 本轮同时换了 applicationId（等于全新安装），本来就不存在迁移数据。
  // 万一将来 Keystore 密钥失效导致读取抛异常，`_AppRoot.initState` 已有兜底：
  // 按「未配对」处理并提示重新扫码，界面不会卡在转圈。
  const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final app = await AndroidAppState.create(
      secureStore: _KeystoreSecureStore(secure));
  // 消费组件（Consumer*）依赖 ProviderScope：缺失时主题切换等依赖
  // 变更会抛「No ProviderScope found」导致整树灰屏。
  runApp(ProviderScope(
    // 真实依赖从这里注入；widget 测试换成内存库 + 假网关。
    overrides: [androidAppProvider.overrideWithValue(app)],
    child: _AppRoot(app: app),
  ));
}

/// 配对 token 走 Keystore 加密存储（SPEC §10）。
class _KeystoreSecureStore implements SecureStore {
  final FlutterSecureStorage _storage;
  _KeystoreSecureStore(this._storage);

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class _AppRoot extends StatefulWidget {
  final AndroidAppState app;

  const _AppRoot({required this.app});

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  PairingInfo? _pairing;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 读取 Keystore 失败（系统升级/换机后 EncryptedSharedPreferences 解不开等）
    // 不能让界面永远停在转圈：失败就按「未配对」处理，走配对页重新扫。
    widget.app.loadPairing().then((p) {
      if (mounted) setState(() { _pairing = p; _loaded = true; });
    }).catchError((Object e) {
      if (mounted) {
        setState(() { _pairing = null; _loaded = true; });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('读取配对信息失败，请重新扫码：$e')));
      }
    });
    // 外观（主题模式/配色）变更时重建 MaterialApp，并强制重发系统栏样式。
    widget.app.settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reassertSystemUi();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _reassertSystemUi();
  }

  /// 「跟随系统」时平台深浅色变了，也要跟着更新系统栏。
  @override
  void didChangePlatformBrightness() => _reassertSystemUi();

  /// Android 会在 Activity 重建、系统弹窗、悬浮球窗口抢焦点等时刻重置窗口的
  /// light-status-bar 标志；回到前台时补一次，避免状态栏一直停在错的颜色上。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reassertSystemUi();
  }

  void _reassertSystemUi() {
    reapplySystemUiOverlayFor(
      widget.app.settings.app.theme,
      widget.app.settings.app.accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.app.settings;
    final themeMode = switch (s.app.theme) {
      ThemeMode2.system => ThemeMode.system,
      ThemeMode2.light => ThemeMode.light,
      ThemeMode2.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      // 系统栏样式随主题（用户需求 4）：AppBar 也换成同一份，
      // 否则 AppBar 自带的黑色导航栏会盖掉透明效果。
      theme: withSystemUiOverlay(QuizSyncTheme.build(
          brightness: Brightness.light, accent: s.app.accent)),
      darkTheme: withSystemUiOverlay(QuizSyncTheme.build(
          brightness: Brightness.dark, accent: s.app.accent)),
      // 主题切换后 `AnnotatedRegion` 随重绘立刻生效，无需重启界面。
      builder: (context, child) =>
          ThemedSystemUi(child: child ?? const SizedBox.shrink()),
      // 初始页自己持有配对状态：配对成功回调切换主页，
      // 而不是 Navigator.pop（pop 掉唯一路由会黑屏）。
      home: !_loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_pairing == null
              ? PairingPage(
                  app: widget.app,
                  onPaired: (info) => setState(() => _pairing = info),
                )
              : AndroidHomePage(
                  pairing: _pairing!,
                  // 重新配对会换掉 token：宿主必须同步更新，否则页面里
                  // 所有上传还在用已作废的 token（表现为「Windows 不在线」）。
                  onRepaired: (info) => setState(() => _pairing = info),
                  // 解除配对 / 设备被吊销：回到配对页。
                  onPairingLost: () => setState(() => _pairing = null),
                )),
    );
  }
}
