import 'package:flutter/services.dart';

/// 系统栏外观桥（M13）：把「底色 + 图标明暗」直接交给自己的 Kotlin 实现
/// （`MainActivity` → `SystemUiBridge`）。
///
/// 为什么不能只靠 `SystemChrome.setSystemUIOverlayStyle`：反编译本机引擎产物
/// （`flutter.jar` → `io.flutter.plugin.platform.PlatformPlugin`）可见
/// `if (Build.VERSION.SDK_INT >= 35) 跳过 window.setStatusBarColor` ——
/// **Android 15 及以上引擎根本不设状态栏底色**，M10/M11 的「显式配色」在那类
/// 机器上必然无效（用户看到的始终是启动窗口主题的默认底色）。
///
/// 这一层只做「把颜色和明暗搬到原生窗口」这一件事，不含任何业务逻辑；
/// 平台通道不可用时（widget 测试、非安卓宿主）静默忽略，界面绝不受影响。
const MethodChannel systemUiChannel = MethodChannel('quizsync/system_ui');

/// 推送一次系统栏样式。
///
/// [dark] 表示**当前主题是深色**（深色 → 状态栏用浅色图标）。
Future<void> pushSystemUiStyle({
  required Color statusBarColor,
  required Color navigationBarColor,
  required bool dark,
}) async {
  try {
    await systemUiChannel.invokeMethod<bool>('setStyle', <String, dynamic>{
      'statusBarColor': statusBarColor.toARGB32(),
      'navigationBarColor': navigationBarColor.toARGB32(),
      'dark': dark,
    });
  } catch (_) {
    // 见上：平台通道只是兜底手段，失败不影响界面。
  }
}
