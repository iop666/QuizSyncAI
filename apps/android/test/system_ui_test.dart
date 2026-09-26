import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show QuizSyncTheme, ThemeMode2;

import 'package:quizsync_android/services/system_ui_channel.dart';
import 'package:quizsync_android/ui/system_ui.dart';

/// 状态栏 / 导航栏跟随主题（用户需求 4 + 用户反馈 11 + 用户反馈 4/M13）。
///
/// 这里**必须断言平台通道上的真实调用**，不能只看 widget 树里的
/// `AnnotatedRegion` 值：上一轮就是这么测的（值都对），可你手机上状态栏依旧不变。
/// 真正的链路是 `AnnotatedRegion → SystemChrome.setSystemUIOverlayStyle →
/// 平台通道 → 系统`，所以下面直接拦 `flutter/platform` 通道抓调用。
///
/// M13 追加两条（原因见 `ui/system_ui.dart` 文件头）：自家 `quizsync/system_ui`
/// 桥上的 payload，以及顶部那条**自绘**的状态栏底色条带。
void main() {
  /// 记录所有 `SystemChrome.setSystemUIOverlayStyle` 调用（含框架自己发的）。
  List<Map<Object?, Object?>> capturePlatformStyles(WidgetTester tester) {
    final calls = <Map<Object?, Object?>>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
        calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  group('样式本身', () {
    test('浅色 = 浅底 + 深图标；深色 = 深底 + 浅图标（颜色不再是透明）', () {
      final light =
          systemUiOverlayStyle(Brightness.light,
              statusBarColor: const Color(0xFFFFFFFF),
              navigationBarColor: const Color(0xFFF3F5F4));
      expect(light.statusBarColor, const Color(0xFFFFFFFF));
      expect(light.statusBarIconBrightness, Brightness.dark);
      // iOS 语义与 Android 相反。
      expect(light.statusBarBrightness, Brightness.light);
      expect(light.systemNavigationBarColor, const Color(0xFFF3F5F4));
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      expect(light.systemStatusBarContrastEnforced, isFalse);

      final dark = systemUiOverlayStyle(Brightness.dark,
          statusBarColor: const Color(0xFF191C1F),
          navigationBarColor: const Color(0xFF0F1113));
      expect(dark.statusBarColor, const Color(0xFF191C1F));
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.statusBarBrightness, Brightness.dark);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    });

    test('从 ThemeData 推出的颜色跟着主题走（状态栏 = AppBar 底色）', () {
      final light = systemUiOverlayStyleOf(
          QuizSyncTheme.build(brightness: Brightness.light, accent: 0xFF16A34A));
      final dark = systemUiOverlayStyleOf(
          QuizSyncTheme.build(brightness: Brightness.dark, accent: 0xFF16A34A));
      expect(light.statusBarColor, isNot(dark.statusBarColor),
          reason: '两种主题的状态栏底色必须不同，否则用户看着「没变」');
      expect(light.systemNavigationBarColor, isNot(dark.systemNavigationBarColor));
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
    });

    test('AppBar 主题用同一份样式（否则 AppBar 会把状态栏刷回去）', () {
      final light = withSystemUiOverlay(
          QuizSyncTheme.build(brightness: Brightness.light, accent: 0xFF16A34A));
      expect(light.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
          Brightness.dark);
      expect(light.appBarTheme.systemOverlayStyle?.statusBarColor,
          light.colorScheme.surface);

      final dark = withSystemUiOverlay(
          QuizSyncTheme.build(brightness: Brightness.dark, accent: 0xFF16A34A));
      expect(dark.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
          Brightness.light);
    });
  });

  group('生效的明暗', () {
    test('跟随系统时以平台亮度为准；显式选浅/深色时以用户选择为准', () {
      expect(effectiveBrightness(ThemeMode2.system, Brightness.dark),
          Brightness.dark);
      expect(effectiveBrightness(ThemeMode2.system, Brightness.light),
          Brightness.light);
      expect(effectiveBrightness(ThemeMode2.light, Brightness.dark),
          Brightness.light);
      expect(effectiveBrightness(ThemeMode2.dark, Brightness.light),
          Brightness.dark);
    });
  });

  group('强制重发（绕开 Flutter 的缓存）', () {
    testWidgets('即使样式没变也要真的发一次平台调用', (tester) async {
      final calls = capturePlatformStyles(tester);
      final style = systemUiOverlayStyle(Brightness.dark,
          statusBarColor: const Color(0xFF191C1F),
          navigationBarColor: const Color(0xFF0F1113));

      // 先走一次普通 API：Dart 侧把它记成「当前样式」。
      SystemChrome.setSystemUIOverlayStyle(style);
      await tester.pump();
      final afterFirst = calls.length;
      expect(afterFirst, greaterThan(0), reason: '第一次必须下发');

      // 再发同一个样式：官方 API 会因为缓存相等而跳过（这正是线上
      // 「Android 重置了窗口标志、Flutter 却不再下发」的根因）。
      SystemChrome.setSystemUIOverlayStyle(style);
      await tester.pump();
      expect(calls.length, afterFirst, reason: '官方 API 的缓存行为');

      // 强制重发：必须真的再发一次。
      reapplySystemUiOverlayStyle(style);
      await tester.pump();
      expect(calls.length, afterFirst + 1, reason: '强制重发必须绕过缓存');
      final last = calls.last;
      expect(last['statusBarColor'], style.statusBarColor!.toARGB32());
      expect(last['statusBarIconBrightness'], 'Brightness.light');
      expect(last['systemNavigationBarColor'],
          style.systemNavigationBarColor!.toARGB32());
      expect(last['systemNavigationBarIconBrightness'], 'Brightness.light');
    });

    testWidgets('按设置重发：深色/浅色两套主题下发的是不同的颜色与图标', (tester) async {
      final calls = capturePlatformStyles(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      reapplySystemUiOverlayFor(ThemeMode2.light, 0xFF16A34A);
      await tester.pump();
      final light = Map<Object?, Object?>.from(calls.last);
      reapplySystemUiOverlayFor(ThemeMode2.dark, 0xFF16A34A);
      await tester.pump();
      final dark = Map<Object?, Object?>.from(calls.last);

      expect(light['statusBarIconBrightness'], 'Brightness.dark');
      expect(dark['statusBarIconBrightness'], 'Brightness.light');
      expect(light['statusBarColor'], isNot(dark['statusBarColor']));
      expect(light['systemNavigationBarColor'],
          isNot(dark['systemNavigationBarColor']));
    });
  });

  testWidgets('原地切主题：平台通道收到的样式确实跟着变（端到端）', (tester) async {
    final calls = capturePlatformStyles(tester);
    final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    addTearDown(mode.dispose);

    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        themeMode: value,
        theme: withSystemUiOverlay(QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A)),
        darkTheme: withSystemUiOverlay(QuizSyncTheme.build(
            brightness: Brightness.dark, accent: 0xFF16A34A)),
        builder: (context, child) =>
            ThemedSystemUi(child: child ?? const SizedBox.shrink()),
        // 页面自带 AppBar：它在状态栏区域画在最上层，样式必须与根节点一致。
        home: Scaffold(appBar: AppBar(title: const Text('当前任务'))),
      ),
    ));
    await tester.pumpAndSettle();

    /// 最后一帧下发到平台的样式。
    String? lastIcons() => calls.isEmpty
        ? null
        : calls.last['statusBarIconBrightness']?.toString();

    expect(lastIcons(), 'Brightness.dark', reason: '浅色主题要下发深色图标');

    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(lastIcons(), 'Brightness.light', reason: '深色主题要下发浅色图标');

    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expect(lastIcons(), 'Brightness.dark', reason: '切回浅色要恢复深色图标');
  });

  /// M13：**Android 15（API 35）起 Flutter 引擎不再设状态栏底色**
  /// （`PlatformPlugin` 里 `if (SDK_INT >= 35) 跳过 window.setStatusBarColor`，
  /// 已用反编译核实），所以 M10/M11 的「显式配色」在那类机器上必然无效。
  /// 对策有两条，下面各测一条：① 图标明暗走自家 Kotlin 桥；② 底色自己画。
  group('自家 Kotlin 桥（图标明暗 / 导航栏）', () {
    List<Map<Object?, Object?>> captureBridgeStyles(WidgetTester tester) {
      final calls = <Map<Object?, Object?>>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      // 框架自己那条 `SystemChrome.setSystemUIOverlayStyle` 也要有处理器，
      // 否则 MissingPluginException 会被 FlutterError 记成测试失败。
      messenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      messenger.setMockMethodCallHandler(systemUiChannel, (call) async {
        if (call.method == 'setStyle') {
          calls.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(systemUiChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      return calls;
    }

    testWidgets('切主题时把颜色与明暗推给原生桥', (tester) async {
      final calls = captureBridgeStyles(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      reapplySystemUiOverlayFor(ThemeMode2.light, 0xFF16A34A);
      await tester.pumpAndSettle();
      expect(calls, hasLength(1), reason: '每次都要真的推一次（系统会重置窗口标志）');
      expect(calls.single['dark'], isFalse, reason: '浅色主题 → 深色图标');
      final lightStatus = calls.single['statusBarColor'];
      final lightNav = calls.single['navigationBarColor'];
      expect(lightStatus, isNotNull);
      expect(lightNav, isNotNull);

      reapplySystemUiOverlayFor(ThemeMode2.dark, 0xFF16A34A);
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls.last['dark'], isTrue, reason: '深色主题 → 浅色图标');
      expect(calls.last['statusBarColor'], isNot(lightStatus));
      expect(calls.last['navigationBarColor'], isNot(lightNav));
    });
  });

  group('自绘状态栏底色条带（平台不认应用配色时的保证）', () {
    /// 顶部 inset = 状态栏高度，只有 edge-to-edge 才有（否则不该画）。
    void useTopInset(WidgetTester tester, double top) {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(top: top);
      tester.view.viewPadding = FakeViewPadding(top: top);
      addTearDown(tester.view.reset);
    }

    Widget app(Brightness brightness) => MaterialApp(
          theme: withSystemUiOverlay(
              QuizSyncTheme.build(brightness: brightness, accent: 0xFF16A34A)),
          builder: (context, child) =>
              ThemedSystemUi(child: child ?? const SizedBox.shrink()),
          home: Scaffold(appBar: AppBar(title: const Text('当前任务'))),
        );

    Color stripColor(WidgetTester tester) => tester
        .widget<ColoredBox>(find.descendant(
          of: find.byKey(ThemedSystemUi.statusStripKey),
          matching: find.byType(ColoredBox),
        ))
        .color;

    testWidgets('状态栏那一条由自己画，颜色跟着主题变，且只盖状态栏高度', (tester) async {
      useTopInset(tester, 24);
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();

      expect(find.byKey(ThemedSystemUi.statusStripKey), findsOneWidget);
      final light = stripColor(tester);
      expect(light, const Color(0xFFFFFFFF), reason: '浅色主题 = 白色 AppBar 底');
      expect(tester.getRect(find.byKey(ThemedSystemUi.statusStripKey)),
          const Rect.fromLTWH(0, 0, 800, 24),
          reason: '只盖状态栏高度，不能压到 AppBar 内容');

      await tester.pumpWidget(app(Brightness.dark));
      await tester.pumpAndSettle();
      expect(stripColor(tester), isNot(light), reason: '深色主题必须换成深色底');
    });

    testWidgets('没有顶部 inset 时不画（窗口本来就没铺到状态栏底下）', (tester) async {
      useTopInset(tester, 0);
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      expect(find.byKey(ThemedSystemUi.statusStripKey), findsNothing);
    });
  });
}
