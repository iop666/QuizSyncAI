import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/state/app_info.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/ui/home_page.dart' show dataRootProvider;
import 'package:quizsync_desktop/ui/settings_page.dart';

/// M9 设置页重构回归：
/// ① 七个分类的左侧导航都在，右侧一次只显示一个分类的内容；
/// ② 点导航就地切换（同一个设置页 state，不重开窗口）；
/// ③ 窄窗口自动收成图标栏，仍然能切换；
/// ④ 最小窗口尺寸下不出现布局溢出；
/// ⑤ 原有功能一个都不少（逐个分类打开并断言关键控件）。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late SettingsController settings;
  late Directory tmp;
  late DesktopServerController server;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
    settings = SettingsController(MemoryKeyValueStore());
    await settings.load();
    tmp = Directory.systemTemp.createTempSync('qs-settings-shell-');
    server = DesktopServerController();
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester,
      {Size size = const Size(1200, 1500)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => settings),
        apiKeyReaderProvider.overrideWithValue(() async => null),
        apiKeyWriterProvider.overrideWithValue((k) async {}),
        serverControllerProvider.overrideWithValue(server),
        dataRootProvider.overrideWithValue(tmp.path),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 切分类：点左导航对应项。用 key 而不是文字——分类名同时出现在
  /// 导航项和右侧页面标题上，按文字找会撞上两个。
  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('settings-nav-$tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('十个分类的导航项都在，默认停在使用说明，且一次只显示一个分类', (tester) async {
    await pumpShell(tester);

    expect(
        SettingsTab.values.map((t) => t.label).toList(),
        [
          // M32 用户需求 5：第一项是「使用说明」，其余顺序整体后延；
          // 悬浮窗设置（用户需求 1）紧跟在悬浮球设置后面。
          '使用说明',
          '显示设置',
          'API 配置',
          '连接设备',
          '识别设置',
          '悬浮球设置',
          '悬浮窗设置',
          '热键设置',
          '数据管理',
          // M46 第 3 条：独立的「赞助」页已删除（赞助支持挪进「关于」页最下面），
          // 所以「关于」重新成为最后一项。
          '关于',
        ]);
    for (final tab in SettingsTab.values) {
      expect(find.byKey(ValueKey('settings-nav-${tab.name}')), findsOneWidget,
          reason: '左导航缺少「${tab.label}」');
    }

    // 默认分类 = 使用说明（用户需求 5）。
    expect(find.text('可识别的五种方式'), findsOneWidget);
    // 其它分类的控件不在树上：右侧只出现当前分类的内容。
    expect(find.byKey(const ValueKey('settings-theme')), findsNothing);
    expect(find.byKey(const ValueKey('settings-multi-page')), findsNothing);
    expect(find.byKey(const ValueKey('settings-api-key')), findsNothing);
    expect(
        find.byKey(const ValueKey('settings-export-collection')), findsNothing);

    await unmount(tester);
  });

  testWidgets('点导航就地切换右侧内容（同一个设置页，不重开窗口）', (tester) async {
    await pumpShell(tester);
    final before = tester.state(find.byType(SettingsPage));

    await openTab(tester, 'recognition');
    expect(find.byKey(const ValueKey('settings-multi-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme')), findsNothing);

    await openTab(tester, 'data');
    expect(find.byKey(const ValueKey('settings-export-collection')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-multi-page')), findsNothing);

    // 左导航始终固定可见，且设置页 state 没被重建。
    expect(find.text('设置'), findsOneWidget);
    expect(identical(tester.state(find.byType(SettingsPage)), before), isTrue,
        reason: '切分类只换右侧内容，不重开设置页');

    await unmount(tester);
  });

  testWidgets('窄窗口收成图标栏，仍然能切换分类', (tester) async {
    await pumpShell(tester, size: const Size(860, 640));
    // 图标栏下导航文字不显示（用 key 判断，避免「使用说明」页里也提到分类名）。
    expect(find.byKey(const ValueKey('settings-api-key')), findsNothing);
    await openTab(tester, 'api');
    expect(find.byKey(const ValueKey('settings-api-key')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('最小窗口尺寸（860×520）下每个分类都不溢出', (tester) async {
    await pumpShell(tester, size: const Size(860, 520));
    for (final tab in SettingsTab.values) {
      await openTab(tester, tab.name);
      expect(tester.takeException(), isNull,
          reason: '「${tab.label}」在最小窗口尺寸下布局溢出');
    }
    await unmount(tester);
  });

  testWidgets('功能清单：十个分类里的原有功能都在', (tester) async {
    await pumpShell(tester);

    // 0 使用说明（M32 用户需求 5）：介绍可识别的方式与各项设置。
    expect(find.text('可识别的五种方式'), findsOneWidget);
    expect(find.textContaining('全局热键截屏'), findsOneWidget);
    expect(find.text('各项设置怎么用'), findsOneWidget);

    // 1 显示设置：主题三态 + 界面缩放 + 题目字号/字重（用户反馈 1/9）。
    await openTab(tester, 'display');
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-font-size-slider')), findsOneWidget);
    // 用户反馈 7：界面缩放改成固定档位下拉框（不再用进度条）。
    expect(find.byKey(const ValueKey('settings-ui-scale-dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-ui-scale-slider')), findsNothing,
        reason: '进度条形式的缩放已按用户要求移除');
    expect(find.byKey(const ValueKey('settings-question-weight-slider')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-question-preview')),
        findsOneWidget, reason: '字重/字号要有实时预览');
    expect(find.byType(AccentPicker), findsNothing,
        reason: '按用户要求删掉的主题配色选择不得回来');
    // 用户反馈 5：每个模块都有可识别的标题带（选项归属一目了然）。
    expect(find.byKey(const ValueKey('settings-module-外观')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-module-题目显示')), findsOneWidget);

    // 2 API 配置：Provider / Key / 模型 / Base URL / 超时 / 上限 / 用量。
    await openTab(tester, 'api');
    for (final key in [
      'settings-provider',
      'settings-api-key',
      'settings-api-key-save',
      'settings-api-key-reveal',
      'settings-model',
      'settings-base-url',
      'settings-timeout',
      'settings-daily-limit',
      'settings-usage',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: 'API 配置缺少 $key');
    }

    // 3 连接设备：M32 用户需求 3 —— 默认关闭，关着时下方功能全部不可用。
    await openTab(tester, 'device');
    expect(find.byKey(const ValueKey('settings-connect-switch')), findsOneWidget);
    expect(settings.app.connectEnabled, isFalse, reason: '连接设备默认关闭');
    expect(find.byKey(const ValueKey('settings-connect-disabled')), findsOneWidget,
        reason: '关着时配对与设备列表要显示为不可用');
    expect(find.byKey(const ValueKey('pairing-code')), findsNothing);
    expect(find.textContaining('同一时间只支持连接一台安卓设备'), findsOneWidget,
        reason: 'M49：换手机的正确顺序要写在设置里（用户反馈）');

    // 4 识别设置：自动识别 / 图片处理 / 多页 / 缓存。
    await openTab(tester, 'recognition');
    for (final key in [
      'settings-clipboard-watch',
      'settings-save-images',
      'settings-multi-page',
      'settings-multi-page-value',
      'settings-image-cache',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '识别设置缺少 $key');
    }
    expect(find.textContaining('最多保留 60 张'), findsOneWidget);

    // 5 悬浮球设置（用户反馈 11）：开关 / 大小 / 透明度 / 描边。
    await openTab(tester, 'ball');
    for (final key in [
      'settings-ball-switch',
      'settings-ball-size-slider',
      'settings-ball-opacity-slider',
      'settings-ball-stroke-switch',
      'settings-ball-stroke-width-slider',
      'settings-ball-stroke-opacity-slider',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '悬浮球设置缺少 $key');
    }

    // 5b 悬浮窗设置（M33）：开关 / 置顶 / 锁定与归位 / 三种外观（单选）/
    //    显示比例 / 窗内字号 / 配色（6 套）/ 明暗模式 / 极简模式 / 透明度。
    //    M33 第 15 条删掉了「拉伸边界」与「一键重置比例」。
    await openTab(tester, 'floatWindow');
    for (final key in [
      'settings-float-switch',
      'settings-float-topmost',
      'settings-float-lock',
      'settings-float-home-button',
      'settings-float-scale-slider',
      'settings-float-font-slider',
      'settings-float-palette',
      'settings-float-theme-segments',
      'settings-float-minimal',
      'settings-float-opacity-slider',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '悬浮窗设置缺少 $key');
    }
    // 三种外观都在（单选），默认是竖屏 9:20。
    for (final aspect in kFloatWindowAspects) {
      expect(find.byKey(ValueKey('settings-float-aspect-${aspect.id}')),
          findsOneWidget,
          reason: '缺少外观「${aspect.label}」');
    }
    expect(settings.app.floatWindowAspect, kDefaultFloatWindowAspect,
        reason: '默认外观是竖屏 9:20（M33 第 1 条）');
    expect(settings.app.floatWindowHeightLogical,
        greaterThan(settings.app.floatWindowWidthLogical),
        reason: '默认竖屏：高大于宽');
    // 三选一：点「横向外观」能切换。
    await tester.tap(find.byKey(const ValueKey('settings-float-aspect-landscape')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.app.floatWindowAspect, 'landscape');
    expect(settings.app.floatWindowHeightLogical,
        lessThan(settings.app.floatWindowWidthLogical));
    // 配色 6 套 + 默认浅色系。
    for (final p in kFloatWindowPalettes) {
      expect(find.byKey(ValueKey('settings-float-palette-${p.id}')),
          findsOneWidget,
          reason: '缺少配色「${p.label}」');
    }
    expect(settings.app.floatWindowPalette, kDefaultFloatWindowPalette);
    expect(find.byKey(const ValueKey('settings-float-stretch')), findsNothing,
        reason: 'M33 第 15 条删掉了拉伸边界');
    expect(find.byKey(const ValueKey('settings-float-ratio-reset')), findsNothing,
        reason: 'M33 第 15 条删掉了重置比例');

    // M46 第 2 条：悬浮窗设置页必须**如实声明**不支持显示公式（公式按 LaTeX
    // 源码显示，要看排版好的公式得回主窗口）。
    final floatTexts = <String>[
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if (w.data != null)
          w.data!
        else if (w.textSpan != null)
          _plainText(w.textSpan!),
    ];
    expect(floatTexts.any((t) => t.contains('悬浮窗不支持显示公式')), isTrue,
        reason: '悬浮窗设置页要写明不支持显示公式（M46 第 2 条）');

    // 6 热键设置：两个槽位都能自定义 + 恢复默认入口（M46 第 1 条）。
    await openTab(tester, 'hotkey');
    expect(find.byKey(const ValueKey('settings-hotkey-capture')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-hotkey-edit-capture')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-hotkey-edit-multipage')),
        findsOneWidget);
    // 用户反馈 10：连点会出 bug 的「重新注册」已换成「恢复默认热键」。
    expect(find.byKey(const ValueKey('settings-hotkey-restore-defaults')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-hotkey-reload')), findsNothing,
        reason: '「重新注册全部热键」按钮已按用户要求移除');
    expect(find.text('多页模式'), findsWidgets,
        reason: '多页模式分组标题 + 槽位行都叫这个名字');
    expect(find.text('截取屏幕并识别'), findsOneWidget);

    // 7 数据管理：合集切换 / 导出合集 / 备份 / 恢复 / 导出历史 / 日志 / 数据目录。
    await openTab(tester, 'data');
    for (final key in [
      'settings-switch-collection',
      'settings-export-collection',
      'settings-export-collection-pick',
      'settings-backup',
      'settings-restore',
      'settings-export-all-md',
      'settings-export-all-json',
      'settings-export-log',
      'settings-copy-data-root',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '数据管理缺少 $key');
    }

    // 8 关于：版本号、品牌图、项目地址与开源许可。
    await openTab(tester, 'about');
    expect(find.byKey(const ValueKey('about-version')), findsOneWidget);
    // M18 第 1 条（用户原话「关于不要写构建 8，这就是 1.0.0 正式版」）：
    // 版本行只有 v1.0.0，不再带「（构建 N）」。
    final versionText =
        tester.widget<Text>(find.byKey(const ValueKey('about-version')));
    expect(versionText.data, 'Windows 桌面版 · v$kAppVersion');
    expect(versionText.data, isNot(contains('构建')));
    expect(find.byKey(const ValueKey('about-logo')), findsOneWidget,
        reason: '用户反馈 13：关于页的图标必须真的显示（用图片资源，不依赖图标字体）');
    // M17 第 2/3 条：显示名改成中文，并补上 GitHub 项目地址。
    expect(find.text('AI 双端搜题'), findsOneWidget, reason: 'M17：默认显示中文名');
    expect(find.textContaining('QuizSync AI'), findsWidgets,
        reason: '项目名仍要出现（GitHub 仓库名就是它）');
    expect(find.byKey(const ValueKey('about-github')), findsOneWidget);
    expect(find.text('https://github.com/iop666/QuizSyncAI'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-licenses')), findsOneWidget);
    // M46 第 3 条（用户要求）：赞助支持是「关于」页的**最后一组**，
    // 填的是用户自己的爱发电地址；独立「赞助」页与收款码图片已整页删除。
    expect(find.byKey(const ValueKey('about-sponsor')), findsOneWidget);
    expect(find.text('https://afdian.com/a/iop666'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-open-sponsor')), findsOneWidget);
    expect(SettingsTab.values.map((t) => t.name), isNot(contains('sponsor')));
    expect(find.byKey(const ValueKey('sponsor-qr-wechat')), findsNothing);

    await unmount(tester);
  });

  testWidgets('M44 第 6 条：所有分类里都不该看到字面的 `**`（渲染成加粗）', (tester) async {
    await pumpShell(tester);
    for (final tab in SettingsTab.values) {
      await openTab(tester, tab.name);
      final visible = <String>[];
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        if (w.data != null) {
          visible.add(w.data!);
        } else if (w.textSpan != null) {
          visible.add(_plainText(w.textSpan!));
        }
      }
      final withStars = visible.where((t) => t.contains('**')).toList();
      expect(withStars, isEmpty,
          reason: '「${tab.label}」里还有字面的星号（应当渲染成加粗）：$withStars');
    }
    await unmount(tester);
  });

  testWidgets('API 配置：每日调用上限可以选「不设上限」（M44 第 2 条）', (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'api');

    final dropdown = find.byKey(const ValueKey('settings-daily-limit'));
    expect(dropdown, findsOneWidget);
    expect(settings.ai.dailyLimit, 200, reason: '默认 200 次');
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('不设上限'), findsWidgets);
    await tester.tap(find.text('不设上限').last);
    await tester.pumpAndSettle();
    expect(settings.ai.dailyLimit, 0, reason: '「不设上限」存 0');
    // 用量显示跟着换文案（不再写成 /0 次）。
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('settings-usage'))).data,
        isNot(contains('/ 0')));

    // 再选回一个具体上限。
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('100').last);
    await tester.pumpAndSettle();
    expect(settings.ai.dailyLimit, 100);

    await unmount(tester);
  });

  testWidgets('悬浮窗：默认模式是默认的显示模式；选白色/紫色会一起切深色', (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'floatWindow');

    // M43 第 1 条：极简（默认模式）就是出厂设置 → 「详细解析模式」开关默认是关的。
    expect(settings.app.floatWindowMinimal, isTrue,
        reason: '默认模式（只看题目与答案）是悬浮窗的默认显示模式');
    final detailSwitch = tester.widget<Switch>(find.descendant(
      of: find.byKey(const ValueKey('settings-float-minimal')),
      matching: find.byType(Switch),
    ));
    expect(detailSwitch.value, isFalse, reason: '「详细解析模式」默认关');

    // 打开「详细解析模式」= 关掉极简。
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('settings-float-minimal')),
      matching: find.byType(Switch),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.app.floatWindowMinimal, isFalse);

    // M43 第 3 条：点「紫罗兰」→ 同时切到深色模式。
    await settings.updateApp(settings.app.copyWith(
        floatWindowTheme: FloatWindowTheme.followApp, floatWindowPalette: 'mint'));
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('settings-float-palette-lilac')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.app.floatWindowPalette, 'lilac');
    expect(settings.app.floatWindowTheme, FloatWindowTheme.dark,
        reason: '选紫色要同时切到深色模式');

    // 选别的配色（薄荷绿）不动用户自己选的明暗模式。
    await tester.tap(
        find.byKey(const ValueKey('settings-float-palette-mint')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.app.floatWindowPalette, 'mint');
    expect(settings.app.floatWindowTheme, FloatWindowTheme.dark,
        reason: '换别的配色不该改明暗模式');

    // 纯净白同样会切深色（用户点名的两套之一）。
    await settings.updateApp(settings.app
        .copyWith(floatWindowTheme: FloatWindowTheme.light));
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('settings-float-palette-white')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.app.floatWindowPalette, 'white');
    expect(settings.app.floatWindowTheme, FloatWindowTheme.dark);

    await unmount(tester);
  });

  testWidgets('连接设备：打开开关后服务未启动时给出明确状态与防火墙提示', (tester) async {
    // M32 用户需求 3：开关关着时连服务都不启动，所以先打开开关再看状态。
    await settings.updateApp(settings.app.copyWith(connectEnabled: true));
    await pumpShell(tester);
    await openTab(tester, 'device');
    expect(find.text('服务未启动'), findsOneWidget);
    expect(find.textContaining('8765–8770'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('连接设备：写着「同时只支持一台安卓设备」与换手机的顺序（用户反馈）',
      (tester) async {
    // 用户原话「windows端同时只能连接一台安卓，设置进行说明」。这里走「开关已打开、
    // 服务还没启动」这一支（开关关着的那一支在页面自检里断言）。
    await settings.updateApp(settings.app.copyWith(connectEnabled: true));
    await pumpShell(tester);
    await openTab(tester, 'device');
    expect(find.textContaining('同一时间只支持连接一台安卓设备'), findsOneWidget,
        reason: '这条说明必须写在设置里，而不是只存在于代码注释');
    expect(find.textContaining('吊销旧设备'), findsOneWidget,
        reason: '换手机的正确顺序（先吊销再配对）要一起写清楚');
    await unmount(tester);
  });

  testWidgets('连接设备：服务启动后给出二维码、配对码与真实连接状态', (tester) async {
    // M32：开关打开才有局域网功能。
    await settings.updateApp(settings.app.copyWith(connectEnabled: true));
    // 真起一个本地服务端（随机端口），连接状态读的就是它的 WS 连接数。
    await tester.runAsync(() async {
      await server.start(
        repo: repo,
        registry: {'openai-compatible': _NoopProvider()},
        aiSettingsReader: () => const AiUiSettings(),
        keyReader: () async => 'sk-test',
        imageDir: tmp.path,
        preferredPort: 0,
      );
    });
    expect(server.server, isNotNull, reason: '测试环境应能起本地服务端');

    await pumpShell(tester);
    await openTab(tester, 'device');
    expect(find.byKey(const ValueKey('pairing-code')), findsOneWidget);
    expect(find.text('等待手机连接'), findsOneWidget,
        reason: '没有设备连着时不能显示「已连接」');
    expect(find.byKey(const ValueKey('settings-copy-pair-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-devices-refresh')), findsOneWidget);
    expect(find.text('暂无设备'), findsOneWidget);
    // M49：服务起来之后这条说明同样在（两个分支都要显示）。
    expect(find.textContaining('同一时间只支持连接一台安卓设备'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('连接设备：手机只走 HTTP 轮询（不建 WS）也算「已连接」（用户实测反馈）', (tester) async {
    await settings.updateApp(settings.app.copyWith(connectEnabled: true));
    late int port;
    await tester.runAsync(() async {
      await server.start(
        repo: repo,
        registry: {'openai-compatible': _NoopProvider()},
        aiSettingsReader: () => const AiUiSettings(),
        keyReader: () async => 'sk-test',
        imageDir: tmp.path,
        preferredPort: 0,
      );
      port = server.port!;
      // flutter_test 的 binding 会把所有 HTTP 请求变成 400（见上面的 Warning），
      // 这一段要真打本地服务端，所以临时摘掉它的 HttpOverrides。
      final saved = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        // 真配对 + 真打一次**需要鉴权**的端点（`/tasks/active` 正是手机端每秒
        // 一次的轮询路径）。走 HTTP 轮询的手机不建 WS，原来的判据（WS 连接数）
        // 会让界面一直显示「等待手机连接」。
        final anon = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
        final paired = await anon.pair(PairRequest(
          code: server.server!.pairingCode,
          deviceId: 'phone-1',
          deviceName: 'Pixel 7',
          platform: 'android',
          appVersion: '1.1.0',
        ));
        await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: paired.token)
            .fetchActiveTask();
      } finally {
        HttpOverrides.global = saved;
      }
    });

    await pumpShell(tester);
    await openTab(tester, 'device');
    expect(find.text('已连接'), findsOneWidget,
        reason: '手机正在轮询主机，就该显示「已连接」（用户实测反馈的那条）');
    expect(find.textContaining('1 台设备在线'), findsOneWidget);
    expect(find.text('等待手机连接'), findsNothing);

    await unmount(tester);
  });
}

/// `Text.rich` 的纯文本（M44 第 6 条那条断言要检查渲染出来的文字里有没有星号）。
String _plainText(InlineSpan span) {
  final buf = StringBuffer();
  void walk(InlineSpan s) {
    if (s is! TextSpan) return;
    if (s.text != null) buf.write(s.text);
    for (final child in s.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  walk(span);
  return buf.toString();
}

/// 不联网的分析替身（本测试不会真的跑任务）。
class _NoopProvider extends QuizAiProvider {  @override
  String get id => 'noop';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async =>
      AiRawResponse(text: '{"questions":[]}', latencyMs: 1);
}
