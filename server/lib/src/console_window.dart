/// 无窗口后台运行用到的控制台操作。
///
/// ## 只是「隐藏窗口」是不够的（用户实测反馈）
///
/// 上一版用 `ShowWindow(SW_HIDE)`：窗口看似没了，但**进程仍然挂在这个控制台上** ——
///   * 在 Windows Terminal / cmd 里启动时，藏掉的是控制台（伪）窗口，终端窗口还在；
///   * 用户关掉那个终端窗口 → 控制台被销毁 → 挂在上面的进程一起被杀（服务就没了）。
///
/// 正确做法是 **`FreeConsole()` 脱离控制台**：进程不再属于任何控制台，窗口随之消失，
/// 之后关掉任何终端都与它无关；日志改由文件承载（见 `Terminal.consoleWithFile`）。
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 彻底脱离控制台：窗口消失，且**之后关掉任何终端都不影响本进程**。
///
/// 返回一句给日志用的说明。
String detachConsoleCompletely() {
  try {
    final hwnd = GetConsoleWindow();
    if (hwnd == 0) {
      // 本来就没有控制台（`--background` 起的、或输出被重定向的）：没什么可脱离的，
      // 而且这种进程从来就不怕关终端。别说成「失败」吓人。
      return '当前没有控制台窗口，进程已独立运行：关掉任何终端都不影响它';
    }
    final hadOwnConsole = _isOwnConsole() && IsWindowVisible(hwnd) != 0;
    if (hadOwnConsole) {
      // 先藏一下：双击启动时窗口会立刻消失，不必等控制台被销毁。
      ShowWindow(hwnd, SW_HIDE);
    }
    final ok = FreeConsole() != 0;
    if (!ok) return '脱离控制台失败：FreeConsole 返回 0（进程仍挂在控制台上）';
    return hadOwnConsole
        ? '已脱离控制台：窗口彻底消失（不是最小化），关闭终端也不会影响它'
        : '已脱离控制台：关闭本终端后它仍会继续运行';
  } catch (e) {
    return '脱离控制台失败：$e';
  }
}

/// 这个控制台是不是我们自己开的（双击 = 只有我们；从终端启动 = 还挂着 shell）。
bool _isOwnConsole() {
  final buffer = calloc<Uint32>(8);
  try {
    return _consoleProcessCount(buffer, 8) == 1;
  } finally {
    calloc.free(buffer);
  }
}

/// `GetConsoleProcessList` 不在 `package:win32` 的导出里（5.x 未暴露），
/// 直接查一次 kernel32。
int _consoleProcessCount(Pointer<Uint32> buffer, int size) {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final fn = kernel32.lookupFunction<
        Uint32 Function(Pointer<Uint32>, Uint32),
        int Function(Pointer<Uint32>, int)>('GetConsoleProcessList');
    return fn(buffer, size);
  } catch (_) {
    return 0; // 查不到就按「不是自己的控制台」处理（保守：不藏用户的终端）
  }
}

