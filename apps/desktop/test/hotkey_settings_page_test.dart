import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/services/floating_ball.dart' show BallState;
import 'package:quizsync_desktop/services/hotkeys.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/ui/home_page.dart' show dataRootProvider;
import 'package:quizsync_desktop/ui/settings/about_settings_page.dart';
import 'package:quizsync_desktop/ui/settings_page.dart';

/// 热键设置页（用户反馈 6 重写；M46 第 1 条改成两个热键）的状态显示回归：
/// 两个槽位、各自的注册结果（生效 / 回退 / 全被占用）、恢复默认入口。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late SettingsController settings;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
    settings = SettingsController(MemoryKeyValueStore());
    await settings.load();
  });

  tearDown(() async => db.close());

  Future<void> pumpHotkeys(
    WidgetTester tester,
    Map<HotkeySlot, HotkeyStatus> statuses, {
    SettingsTab tab = SettingsTab.hotkey,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        repoProvider.overrideWithValue(repo),
        settingsProvider.overrideWith((ref) => settings),
        apiKeyReaderProvider.overrideWithValue(() async => null),
        apiKeyWriterProvider.overrideWithValue((k) async {}),
        serverControllerProvider.overrideWithValue(DesktopServerController()),
        dataRootProvider.overrideWithValue(Directory.systemTemp.path),
        hotkeyStatusProvider.overrideWith((ref) => statuses),
      ],
      child: MaterialApp(home: SettingsPage(initialTab: tab)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('两个槽位都在，并显示各自实际生效的组合键（默认 F8 / F9）', (tester) async {
    await pumpHotkeys(tester, {
      HotkeySlot.capture: const HotkeyStatus(
          slot: HotkeySlot.capture,
          activeLabel: 'F8',
          outcome: HotkeyOutcome.active),
      HotkeySlot.multipage: const HotkeyStatus(
          slot: HotkeySlot.multipage,
          activeLabel: 'F9',
          outcome: HotkeyOutcome.active),
    });

    for (final slot in HotkeySlot.values) {
      expect(find.byKey(ValueKey('settings-hotkey-${slot.name}')), findsOneWidget,
          reason: '缺少「${slot.title}」这一行');
      expect(find.byKey(ValueKey('settings-hotkey-edit-${slot.name}')),
          findsOneWidget);
    }
    // 键帽是「一个键一个方块」，所以按 label 取回组件来断言组合键。
    String capsOf(HotkeySlot s) => tester
        .widget<SettingsKeycaps>(
            find.byKey(ValueKey('settings-hotkey-caps-${s.name}')))
        .label;
    expect(capsOf(HotkeySlot.capture), 'F8');
    expect(capsOf(HotkeySlot.multipage), 'F9');
    expect(find.text('默认热键已生效'), findsNWidgets(2));

    await unmount(tester);
  });

  testWidgets('候选键全被占用：行内给出占位提示 + 明确说明走托盘菜单', (tester) async {
    await pumpHotkeys(tester, {
      HotkeySlot.capture: const HotkeyStatus(
          slot: HotkeySlot.capture, outcome: HotkeyOutcome.noCandidate),
      HotkeySlot.multipage: const HotkeyStatus(
          slot: HotkeySlot.multipage, outcome: HotkeyOutcome.noCandidate),
    });

    // 每个槽位都有一条黄色警示，两处都点名「托盘菜单」这个兜底入口。
    expect(find.textContaining('候选热键都被其他程序占用'), findsNWidgets(2));
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));

    await unmount(tester);
  });

  testWidgets('自定义键被占用 → 显示回退说明，并给「恢复默认」入口', (tester) async {
    await settings.updateApp(
        settings.app.copyWith(hotkeyJson: '{"key":{"usageCode":64}}'));
    await pumpHotkeys(tester, {
      HotkeySlot.capture: const HotkeyStatus(
          slot: HotkeySlot.capture,
          activeLabel: 'F8',
          customLabel: 'Ctrl+Alt+F7',
          customError: '被其他程序占用',
          outcome: HotkeyOutcome.customTaken),
    });

    expect(find.textContaining('已被其他程序占用'), findsOneWidget);
    expect(find.textContaining('已自动改用 F8'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-hotkey-auto-capture')),
        findsOneWidget, reason: '设置了自定义键才出现「恢复默认」');
    expect(find.text('修改'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('「恢复默认」按钮：设过自定义键才可点，点完清掉两个槽位', (tester) async {
    await settings.updateApp(settings.app.copyWith(
      hotkeyJson: '{"key":{"usageCode":64}}',
      multipageHotkeyJson: '{"key":{"usageCode":65}}',
    ));
    await pumpHotkeys(tester, const {});

    final button = find.byKey(const ValueKey('settings-hotkey-restore-defaults'));
    expect(button, findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull,
        reason: '设过自定义键时按钮可用');

    await tester.tap(button);
    await tester.pump();
    expect(settings.app.hotkeyJson, isNull);
    expect(settings.app.multipageHotkeyJson, isNull);
    // 清空后没有自定义键 → 按钮变灰（不再有可恢复的东西）。
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('settings-hotkey-restore-defaults')))
            .onPressed,
        isNull);

    await unmount(tester);
  });

  testWidgets('用户反馈 5 / M31：停在本页时热键触发被忽略，离开页面自动恢复', (tester) async {
    // 自己持有 container：页面卸载后 ProviderScope 会一起销毁，
    // 那时再 containerOf 就读不到了。
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      repoProvider.overrideWithValue(repo),
      settingsProvider.overrideWith((ref) => settings),
      apiKeyReaderProvider.overrideWithValue(() async => null),
      apiKeyWriterProvider.overrideWithValue((k) async {}),
      serverControllerProvider.overrideWithValue(DesktopServerController()),
      dataRootProvider.overrideWithValue(Directory.systemTemp.path),
      hotkeyStatusProvider.overrideWith((ref) => const {}),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage(initialTab: SettingsTab.hotkey)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(hotkeysSuspendedProvider), isTrue,
        reason: '热键设置页挂载后要登记「本页正开着」（否则设置时会真的截屏）');

    await unmount(tester);
    expect(container.read(hotkeysSuspendedProvider), isFalse,
        reason: '离开热键设置页要清掉登记（触发立刻恢复）');
  });

  testWidgets('图标资源可用：托盘 ICO + 应用 ICO + 关于页 PNG 都是合法资源', (tester) async {
    // 这几份资源是「图标丢失」类问题的关键（用户反馈 8/13/4 + 本轮 1/4）：
    // 一个给托盘、一个给任务栏（必须带圆角透明角），一个给关于页。
    final ico = await rootBundle.load('assets/statusbar.ico');
    final bytes = ico.buffer.asUint8List(ico.offsetInBytes, ico.lengthInBytes);
    expect(bytes.length, greaterThan(10 * 1024));
    expect(bytes.sublist(0, 4), [0, 0, 1, 0], reason: 'ICO 文件头');
    final frames = bytes[4] | (bytes[5] << 8);
    expect(frames, greaterThanOrEqualTo(4), reason: '多尺寸帧，系统小图标才清晰');

    // 用户反馈 1/4：应用程序图标（任务栏 + 关于页）是另一枚图，同样多尺寸，
    // 且**圆角外的像素必须是透明的**（Windows 不会替应用图标加圆角）。
    final appIco = await rootBundle.load('windows/runner/resources/app_icon.ico');
    final appIcoBytes =
        appIco.buffer.asUint8List(appIco.offsetInBytes, appIco.lengthInBytes);
    expect(appIcoBytes.sublist(0, 4), [0, 0, 1, 0], reason: '应用 ICO 文件头');
    expect(appIcoBytes[4] | (appIcoBytes[5] << 8), greaterThanOrEqualTo(4));

    final png = await rootBundle.load('assets/app_icon.png');
    final pngBytes =
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    expect(pngBytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10],
        reason: 'PNG 文件头');

    // 关于页用的是**应用图标图片**（用户反馈 4），不再依赖图标字体。
    await pumpHotkeys(tester, const {}, tab: SettingsTab.about);
    expect(find.byKey(const ValueKey('about-logo-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-font-misans')), findsOneWidget,
        reason: '用户反馈 6：关于页必须声明所用字体与协议');
    expect(find.textContaining('MiSans'), findsWidgets);
    // 用户反馈 12：MiSans 许可地址末尾不能多一个斜杠。
    expect(AboutSettingsPage.misansFaqUrl, 'https://hyperos.mi.com/font/faq');
  });

  testWidgets('用户反馈 1：托盘（状态栏）图标也是圆角 —— 圆角外像素必须透明', (tester) async {
    final data = await rootBundle.load('assets/statusbar.ico');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final frame = _firstIcoFrame(bytes);
    expect(frame, isNotNull, reason: 'statusbar.ico 至少要有一帧');
    // 16×16 帧的左上角必须在圆角之外（alpha = 0）。源图是白底不透明，
    // 不做圆角遮罩的话这里会是 255 —— 就是用户报的「状态栏图标不是圆角」。
    expect(frame!.alphaAt(0, 0), lessThan(16),
        reason: '托盘图标左上角必须透明（圆角）');
    expect(frame.alphaAt(8, 8), greaterThan(200), reason: '图标中心必须实心');
  });

  testWidgets('用户反馈 11：悬浮球三态资源都已去掉白底、裁成圆形', (tester) async {
    for (final state in BallState.values) {
      final data = await rootBundle.load(state.asset);
      final image = img.decodePng(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      expect(image, isNotNull, reason: '${state.asset} 不是合法 PNG');
      final im = image!;
      expect(im.getPixel(0, 0).a, lessThan(16),
          reason: '${state.label}：四角必须透明（白底已去掉）');
      expect(im.getPixel(im.width - 1, im.height - 1).a, lessThan(16));
      expect(im.getPixel(im.width ~/ 2, im.height ~/ 2).a, greaterThan(200),
          reason: '${state.label}：球体中心必须不透明');
    }
  });
}

/// ICO 的第一帧（最小尺寸那帧）的极简解析器：只为了断言圆角外的 alpha。
class _IcoFrame {
  final int width;
  final int height;
  final Uint8List bgra;
  _IcoFrame(this.width, this.height, this.bgra);

  int alphaAt(int x, int y) {
    // DIB 帧是自下而上存的：图像第 y 行对应缓冲区第 (height-1-y) 行。
    final row = height - 1 - y;
    return bgra[(row * width + x) * 4 + 3];
  }
}

_IcoFrame? _firstIcoFrame(Uint8List ico) {
  final count = ico[4] | (ico[5] << 8);
  if (count < 1) return null;
  // 第一个目录项：宽 高 颜色数 保留 平面 位深 数据长度 数据偏移
  final size = ico[6] == 0 ? 256 : ico[6];
  final offset = ico[18] | (ico[19] << 8) | (ico[20] << 16) | (ico[21] << 24);
  if (size >= 256) return null; // 只解析 BMP 帧
  final dib = offset + 40; // 跳过 BITMAPINFOHEADER
  final pixels = Uint8List(size * size * 4);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = ico[dib + i];
  }
  return _IcoFrame(size, size, pixels);
}
