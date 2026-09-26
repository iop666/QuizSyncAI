import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 纯文本 CLI 的输出层。
///
/// Server 的一切输出都从这里出去，三件事必须做对：
///  1. **UTF-8**：中文与二维码用的半块字符（`▀`）必须按 UTF-8 写字节，
///     否则在中文 Windows 的控制台上会变成乱码（Dart 的 `stdout` 默认用系统
///     代码页编码）；
///  2. **VT 转义**：二维码靠 ANSI 背景色渲染，Windows 控制台默认不解析转义序列，
///     要在启动时打开 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`；
///  3. **可注入**：单测直接构造一个内存 sink，不碰真实控制台。
class Terminal {
  final void Function(List<int> bytes) _writeBytes;

  /// 转后台时要摘掉的那一路输出（把控制台一路关掉，只留文件）。
  void Function()? _detachFromConsole;

  /// 退出时收尾（文件日志要关句柄）。
  void Function()? _closeSink;

  /// 是否已经开启过控制台的 VT 解析（重复开启是幂等的，只是省一次系统调用）。
  static bool _vtEnabled = false;

  Terminal._(this._writeBytes);

  /// 真实控制台。
  factory Terminal.console() => Terminal._((bytes) => stdout.add(bytes));

  /// 单测/重定向用：把输出收进一个内存缓冲。
  factory Terminal.buffer(StringBuffer buffer) =>
      Terminal._((bytes) => buffer.write(utf8.decode(bytes)));

  /// 后台（无窗口）模式：只写日志文件。
  ///
  /// 无窗口运行时 stdout 没人看（甚至已经没有控制台了），所以一切照旧写进
  /// `<数据目录>\server.log`。文件超过 [maxBytes] 就先轮转一份 `.1`，
  /// 免得长期后台运行把磁盘写满。
  ///
  /// **句柄要一直开着**：日志是逐行写的，一次 `writeAsBytesSync` 就是「开文件 →
  /// 写 → flush → 关文件」，二维码那段三四十行就变成三四十次开关文件（实测会明显
  /// 拖慢启动输出，本机杀毒软件还要每次查一遍）。改成启动时开一次 `RandomAccessFile`、
  /// 每行只 `writeFromSync + flushSync`，输出速度回到原来那样。
  factory Terminal.file(File file, {int maxBytes = 4 * 1024 * 1024}) {
    var size = file.existsSync() ? file.lengthSync() : 0;
    RandomAccessFile? handle;
    void closeHandle() {
      try {
        handle?.closeSync();
      } catch (_) {}
      handle = null;
    }

    final t = Terminal._((bytes) {
      try {
        if (size > maxBytes) {
          closeHandle(); // 轮转前必须先松开句柄，否则 rename 会失败
          final rotated = File('${file.path}.1');
          if (rotated.existsSync()) rotated.deleteSync();
          if (file.existsSync()) file.renameSync(rotated.path);
          size = 0;
        }
        handle ??= file.openSync(mode: FileMode.append);
        // 每次写之前先把写指针挪到当前文件末尾：同一份 `server.log` 可能被两个实例
        // 同时写着（用户点第二次启动、旧实例还没退出时就会这样），而句柄各自的写指针
        // 是独立的 —— 不重新定位的话后写的那一方会**覆盖**对方的段落，日志变成
        // 「同一块状态刷了几十遍」那种错乱样子（M45f 实测在用户数据目录里见到）。
        handle!.setPositionSync(handle!.lengthSync());
        handle!.writeFromSync(bytes);
        handle!.flushSync();
        size += bytes.length;
      } catch (_) {
        // 日志写不进去也绝不能让服务挂掉。句柄坏了就丢掉，下次重新开。
        closeHandle();
      }
    });
    t._closeSink = closeHandle;
    return t;
  }

  /// 同时写两处（后台模式：日志文件 + 控制台）。
  ///
  /// 后台运行不代表日志就没用了：从终端启动时用户还能看见，双击启动时控制台窗口
  /// 会自己消失，日志仍然完整写进 `<数据目录>\server.log`。
  factory Terminal.tee(Terminal a, Terminal b) {
    final t = Terminal._((bytes) {
      a._writeBytes(bytes);
      b._writeBytes(bytes);
    });
    t._closeSink = () {
      a.close();
      b.close();
    };
    return t;
  }

  /// 控制台 + 文件（`--hidden` / `hidden` 用）。
  ///
  /// 三点讲究：
  ///  1. **没有控制台就别写控制台**：`ProcessStartMode.detached` 起的后台进程
  ///     stdout 是无效句柄，写进去会抛异步错误、把整个进程带崩 —— 启动时看一次
  ///     `GetConsoleWindow()` 就能判掉，无控制台时退化成纯文件日志；
  ///  2. `detachFromConsole()` 之后**彻底不再写控制台**（此时控制台已被
  ///     `FreeConsole` 抛弃，写进去同样会出错）；
  ///  3. 文件那一路永远不会失败（见 [Terminal.file]），所以脱离控制台不影响留证。
  factory Terminal.consoleWithFile(File file) {
    final fileSink = Terminal.file(file);
    var toConsole = _hasConsole();
    final t = Terminal._((bytes) {
      fileSink._writeBytes(bytes);
      if (toConsole) {
        try {
          stdout.add(bytes);
        } catch (_) {
          toConsole = false; // 写不动就永久关掉这一路，别让日志把服务搞崩
        }
      }
    });
    t._detachFromConsole = () => toConsole = false;
    t._closeSink = fileSink.close;
    return t;
  }

  /// 脱离控制台之后调用：从此只写日志文件。
  void detachFromConsole() => _detachFromConsole?.call();

  /// 退出前收尾：把文件日志的句柄关掉（内容早已逐行 flush，不会丢）。
  void close() => _closeSink?.call();

  /// 把已经排进 stdout 的内容推出去（转后台前调一次，否则最后几行提示可能丢）。
  Future<void> flush() async {
    try {
      await stdout.flush();
    } catch (_) {}
  }

  /// 本进程当前有没有控制台（双击 = 有；`detached` 启动 = 没有）。
  static bool _hasConsole() {
    try {
      return GetConsoleWindow() != 0;
    } catch (_) {
      return false;
    }
  }

  /// 打开 VT 转义解析 + UTF-8 输出代码页（失败静默：老系统上二维码会花，
  /// 其余功能照常）。
  static void enableAnsiConsole() {
    if (_vtEnabled) return;
    _vtEnabled = true;
    try {
      final handle = GetStdHandle(STD_OUTPUT_HANDLE);
      if (handle != 0 && handle != INVALID_HANDLE_VALUE) {
        final mode = calloc<Uint32>();
        try {
          if (GetConsoleMode(handle, mode) != 0) {
            SetConsoleMode(
                handle, mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
          }
        } finally {
          calloc.free(mode);
        }
      }
    } catch (_) {}
    _setOutputCodePage(65001); // UTF-8
  }

  /// `SetConsoleOutputCP` 不在 `package:win32` 的导出里（5.x 未暴露），
  /// 直接查一次 kernel32 即可；拿不到就静默跳过（控制台仍是系统代码页，
  /// 中文可能显示成乱码，但功能不受影响）。
  static void _setOutputCodePage(int codePage) {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final setOutputCp = kernel32.lookupFunction<
          Int32 Function(Uint32),
          int Function(int)>('SetConsoleOutputCP');
      setOutputCp(codePage);
    } catch (_) {}
  }
  void write(String text) => _writeBytes(utf8.encode(text));

  void line([String text = '']) => write('$text\n');

  /// 唯一的一行日志格式：`[Server] Started on 192.168.1.100:8765`。
  void log(String tag, String message) => line('[$tag] $message');

  /// 错误一律走 `[Error]`，并且**永远**同时给一句人能看懂的原因。
  void error(String message) => log('错误', message);

  /// 覆盖当前行的简易进度提示（例如「[AI] Processing...」）。
  void progress(String tag, String message) =>
      write('\r\x1b[2K[$tag] $message');

  void clearProgressLine() => write('\r\x1b[2K');
}
