import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show QuizSyncTheme, ThemeMode2;

import '../services/system_ui_channel.dart';

/// 系统栏（状态栏 / 导航栏）样式跟随当前主题。
///
/// 这里踩过三次坑，结论写清楚，别再走回头路：
///
/// 1. **必须显式给颜色**。原来只设 `transparent` + 图标明暗，靠「内容画到
///    状态栏底下」透出 AppBar 的颜色。可在不少 ROM 上（尤其是 Android 15
///    强制 edge-to-edge 之后）透明状态栏只让**图标**变明暗，用户看到的仍是
///    一块与主题无关的底色，观感就是「切了深色状态栏没跟着变」。
///
/// 2. **必须在主题变化 / 回到前台时强制重发**。`SystemChrome.
///    setSystemUIOverlayStyle` 在 Dart 侧有 `_latestStyle` 缓存：值没变就
///    不发平台调用。而 Android 会重置窗口的 light-status-bar 标志
///    （Activity 重建、系统权限弹窗、悬浮球这类别的窗口抢焦点、录屏授权返回），
///    这时窗口已经是错的，Flutter 却认为「已经是这个样式了」不再下发 ——
///    表现就是状态栏一直停在错的主题色上。所以 [reapplySystemUiOverlayStyle]
///    除了走正常路径，还会直接经平台通道重发一次，绕过这个缓存。
///
/// 3. **前两条在 Android 15+ 上都不够**（M13 用反编译拿到的证据）：本机引擎
///    产物里的 `PlatformPlugin` 写着 `if (SDK_INT >= 35) 跳过 setStatusBarColor`
///    —— 平台 15 起状态栏底色由「内容自己画」决定，颜色怎么下发都没用。于是：
///    ① 图标明暗走自家 Kotlin 桥 [pushSystemUiStyle]（`WindowInsetsControllerCompat`，
///    未废弃，且在窗口获焦时由宿主重贴）；
///    ② 底色由 [ThemedSystemUi] 在顶部安全区**自己画一条同色条带**。
///    这样无论平台版本、ROM、引擎行为如何，用户看到的底色与图标明暗都由主题决定。
SystemUiOverlayStyle systemUiOverlayStyle(
  Brightness brightness, {
  /// 状态栏底色（取 AppBar / surface 色）。
  required Color statusBarColor,

  /// 导航栏底色（取画布色）。
  required Color navigationBarColor,
}) {
  final dark = brightness == Brightness.dark;
  // 浅色主题 = 浅底深图标；深色主题 = 深底浅图标。
  final iconBrightness = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: statusBarColor,
    // Android 看 statusBarIconBrightness，iOS 看 statusBarBrightness（语义相反）。
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: navigationBarColor,
    systemNavigationBarDividerColor: navigationBarColor,
    systemNavigationBarIconBrightness: iconBrightness,
    // 明确禁止系统再叠一层对比度遮罩，否则浅色主题下状态栏会被压成一块深色。
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 从一份 [ThemeData] 推出它对应的系统栏样式（两端只有安卓用得上，
/// 但放在共享包里方便单测）。
SystemUiOverlayStyle systemUiOverlayStyleOf(ThemeData theme) =>
    systemUiOverlayStyle(
      theme.brightness,
      statusBarColor: theme.appBarTheme.backgroundColor ??
          theme.colorScheme.surface,
      navigationBarColor: theme.scaffoldBackgroundColor,
    );

/// 「跟随系统」时以平台亮度为准，否则用用户选的模式。
/// 单独抽出来是为了能脱离 widget 直接单测。
Brightness effectiveBrightness(ThemeMode2 mode, Brightness platform) =>
    switch (mode) {
      ThemeMode2.system => platform,
      ThemeMode2.light => Brightness.light,
      ThemeMode2.dark => Brightness.dark,
    };

/// 把系统栏样式写进 [ThemeData]：`AppBar` 自带的 `AnnotatedRegion`
/// 与 [ThemedSystemUi] 会给出同一份样式（否则 AppBar 会把导航栏刷回黑色）。
ThemeData withSystemUiOverlay(ThemeData theme) => theme.copyWith(
      appBarTheme: theme.appBarTheme
          .copyWith(systemOverlayStyle: systemUiOverlayStyleOf(theme)),
    );

/// 让整棵子树按当前主题声明系统栏样式（声明式，负责按路由/页面自动切换）。
///
/// **同时在顶部安全区自绘一条状态栏底色的条带**（M13）：Android 15 起平台不认
/// 「应用指定的状态栏底色」，状态栏区域显示的就是应用自己画的内容，所以这条
/// 条带才是底色真正跟随主题的保证；它画在最上层、且不吞触摸事件。
/// 没有顶部 inset（窗口没铺到状态栏底下）时不画 —— 那种情况由平台/原生桥负责。
class ThemedSystemUi extends StatelessWidget {
  final Widget child;

  const ThemedSystemUi({super.key, required this.child});

  /// 状态栏底色条带（单测按 key 找它）。
  static const Key statusStripKey = ValueKey('system-ui-status-strip');

  @override
  Widget build(BuildContext context) {
    final style = systemUiOverlayStyleOf(Theme.of(context));
    final top = MediaQuery.paddingOf(context).top;
    final strip = top > 0 ? style.statusBarColor : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: strip == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(child: child),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: top,
                  child: IgnorePointer(
                    child: SizedBox(
                      key: statusStripKey,
                      child: ColoredBox(color: strip),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// **强制**把样式下发给平台，绕过 Flutter 的 `_latestStyle` 缓存。
///
/// 调用时机：主题切换、App 回到前台、平台亮度变化、首帧之后。
/// 第一句走官方 API（保持 Flutter 自己的缓存一致），第二句直接发平台通道
/// —— 平台通道的入参格式就是 `PlatformPlugin` 读取的那几个键，是引擎契约，
/// 不是实现细节；即便将来引擎改了，异常也只是被忽略，界面照常。
/// 第三句发自家 Kotlin 桥：**Android 15+ 只有这条路径真的能改到状态栏**
/// （引擎不设底色，窗口标志又会被系统重置，见文件头注释第 3 条）。
void reapplySystemUiOverlayStyle(SystemUiOverlayStyle style) {
  SystemChrome.setSystemUIOverlayStyle(style);
  try {
    SystemChannels.platform
        .invokeMethod<void>('SystemChrome.setSystemUIOverlayStyle', <String, dynamic>{
      'systemNavigationBarColor': style.systemNavigationBarColor?.toARGB32(),
      'systemNavigationBarDividerColor':
          style.systemNavigationBarDividerColor?.toARGB32(),
      'systemStatusBarContrastEnforced': style.systemStatusBarContrastEnforced,
      'statusBarColor': style.statusBarColor?.toARGB32(),
      'statusBarBrightness': style.statusBarBrightness?.toString(),
      'statusBarIconBrightness': style.statusBarIconBrightness?.toString(),
      'systemNavigationBarIconBrightness':
          style.systemNavigationBarIconBrightness?.toString(),
      'systemNavigationBarContrastEnforced':
          style.systemNavigationBarContrastEnforced,
    }).catchError((Object _) {
      // 老引擎/测试环境可能没有这个通道：静默忽略，绝不影响界面。
    });
  } catch (_) {
    // 见上：强制重发只是兜底手段。
  }
  // 自家桥（M13）：API 35+ 上这是唯一真正改得到状态栏的路径，必须每次重发。
  final statusBarColor = style.statusBarColor;
  final navigationBarColor = style.systemNavigationBarColor;
  if (statusBarColor != null && navigationBarColor != null) {
    unawaited(pushSystemUiStyle(
      statusBarColor: statusBarColor,
      navigationBarColor: navigationBarColor,
      // 状态栏用浅色图标 ⇒ 当前主题是深色。
      dark: style.statusBarIconBrightness == Brightness.light,
    ));
  }
}

/// 按当前主题与用户设置，重发一次系统栏样式（主题变化 / 回到前台时调）。
void reapplySystemUiOverlayFor(ThemeMode2 mode, int accent) {
  final brightness = effectiveBrightness(
    mode,
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
  final theme = QuizSyncTheme.build(brightness: brightness, accent: accent);
  reapplySystemUiOverlayStyle(systemUiOverlayStyleOf(theme));
}
