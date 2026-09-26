import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'state/app_info.dart';
import 'state/app_scope.dart';
import 'state/capture_coordinator.dart';
import 'ui/collection_picker_page.dart';
import 'ui/home_page.dart';

/// 桌面滚动行为：允许鼠标拖拽滚动（Windows 上 Flutter 默认只认滚轮，
/// 「按住列表拖动」这种桌面常规操作原本不可用）。
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// 界面缩放（用户反馈 9）：50%–300%。
///
/// 做法是「虚拟画布 + 等比放大」：把 MediaQuery 的逻辑尺寸除以缩放比、
/// devicePixelRatio 乘上缩放比，再等比放大画布。文字与控件一起缩放，
/// 布局里所有断点（例如设置页 880 的收栏阈值）按缩放后的逻辑尺寸判断。
///
/// **必须用 `OverflowBox` 把虚拟画布撑开**（用户反馈 M14 第 1 条「还是那片黑」）：
/// 根节点给下来的是**紧约束**（= 窗口逻辑尺寸），直接在 `Transform.scale` 里放
/// `SizedBox(virtual)` 会被紧约束夹回窗口尺寸 —— 于是界面按窗口尺寸布局、再被
/// 缩小到一半，只画在左上角，右边/下边留下一条**没有任何 widget 覆盖的区域**
/// （引擎的清屏色，深色主题下就是那片黑）。`OverflowBox` 用虚拟尺寸去布局子树，
/// 缩放后的绘制结果正好铺满窗口。
class UiScale extends StatelessWidget {
  final double scale;
  final Widget child;

  const UiScale({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if ((scale - 1.0).abs() < 0.001) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        final virtual = Size(
          constraints.maxWidth / scale,
          constraints.maxHeight / scale,
        );
        return MediaQuery(
          data: mq.copyWith(
            size: virtual,
            devicePixelRatio: mq.devicePixelRatio * scale,
          ),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: virtual.width,
            maxWidth: virtual.width,
            minHeight: virtual.height,
            maxHeight: virtual.height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 根组件：主题三态 + MiSans 字体 + 界面缩放 + 图片拖入（SPEC 2.1）。
/// 剪贴板粘贴图片由 ClipboardWatcher 自动分析，无需按键。
class QuizSyncApp extends ConsumerWidget {
  final CaptureCoordinator coordinator;

  /// MaterialApp 的 navigatorKey：托盘/热键等无 context 入口
  /// 靠它拿到 Navigator 作用域来弹窗（「框选重试」等）。
  final GlobalKey<NavigatorState> navigatorKey;

  const QuizSyncApp({
    super.key,
    required this.coordinator,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = switch (settings.app.theme) {
      ThemeMode2.system => ThemeMode.system,
      ThemeMode2.light => ThemeMode.light,
      ThemeMode2.dark => ThemeMode.dark,
    };
    // 用户反馈 1：Windows 端整体用 MiSans（随包附带的可变字体），
    // 系统字体只作兜底（字体文件缺失/缺字时仍有中文可读）。
    const mixture = ['Microsoft YaHei UI', 'Segoe UI', 'Microsoft YaHei'];
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: themeMode,
      scrollBehavior: const _DesktopScrollBehavior(),
      theme: QuizSyncTheme.build(
          brightness: Brightness.light,
          accent: settings.app.accent,
          fontFamily: 'MiSans',
          fontFamilyFallback: mixture),
      darkTheme: QuizSyncTheme.build(
          brightness: Brightness.dark,
          accent: settings.app.accent,
          fontFamily: 'MiSans',
          fontFamilyFallback: mixture),
      // 用户反馈 9：界面缩放对所有路由（含设置页与弹窗）生效。
      builder: (context, child) => UiScale(
        scale: settings.app.uiScale,
        child: child ?? const SizedBox.shrink(),
      ),
      // 用户需求 8：没有选中合集时挡在合集选择页，不进主界面。
      home: CollectionGate(
        child: DropTarget(
          onDragDone: (details) async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            for (final file in details.files) {
              final path = file.path;
              final ext = path.toLowerCase().split('.').last;
              if (!['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'].contains(ext)) {
                messenger?.showSnackBar(SnackBar(
                    content: Text('只支持图片文件（png/jpg/bmp/webp/gif）：$ext')));
                continue;
              }
              try {
                final bytes = await File(path).readAsBytes();
                await coordinator.analyzeBytes(bytes, source: '拖入图片');
              } catch (e) {
                // 原来静默吞掉：拖入损坏/被占用/超大文件时用户完全没反馈。
                messenger?.showSnackBar(
                    SnackBar(content: Text('无法读取该图片：$e')));
              }
            }
          },
          child: HomePage(
            onCapture: coordinator.captureAndAnalyze,
            coordinator: coordinator,
          ),
        ),
      ),
    );
  }
}
