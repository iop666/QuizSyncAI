import 'dart:collection';
import 'dart:io';

import 'ids.dart';

/// 应用日志（M6 任务 10）：环形缓冲 + 文件导出。
/// **绝不**记录 API Key 与 token（redact 兜底）。
///
/// M12：增加**落盘**（[attachFile]）。原来日志只在内存里，用户报障时
/// 「导出日志」本身一旦失败就什么也拿不到（本轮「导出全部失败」就是这么
/// 卡住的）；现在启动时挂一个文件 sink，任何一条日志都同时写进
/// `<数据目录>/logs/app.log`，排查时直接看文件。
class AppLogger {
  static final AppLogger instance = AppLogger();

  final int capacity;
  final Queue<(int, String, String)> _entries = Queue();

  /// 落盘目标（null = 只留内存）。写入失败一律忽略，绝不影响主流程。
  IOSink? _sink;

  /// 单个日志文件的上限；超过就在挂载时截断重来（避免无限增长）。
  static const int maxFileBytes = 2 * 1024 * 1024;

  AppLogger({this.capacity = 2000});

  /// 把日志同时写到 [path]（父目录自动创建）。失败时静默退回纯内存。
  void attachFile(String path) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxFileBytes) {
        file.writeAsStringSync('', flush: true);
      }
      _sink?.close();
      _sink = file.openWrite(mode: FileMode.append);
      _filePath = path;
    } catch (_) {
      _sink = null;
      _filePath = null;
    }
  }

  void detachFile() {
    try {
      _sink?.close();
    } catch (_) {}
    _sink = null;
    _filePath = null;
  }

  /// 落盘路径（设置页「打开日志目录」用）；没挂文件时为 null。
  String? get filePath => _filePath;
  String? _filePath;

  void info(String tag, String message) => _add('I', tag, message);
  void warn(String tag, String message) => _add('W', tag, message);
  void error(String tag, String message) => _add('E', tag, message);

  void _add(String level, String tag, String message) {
    if (_entries.length >= capacity) {
      _entries.removeFirst();
    }
    final safe = redact('$tag: $message');
    final at = nowMs();
    _entries.add((at, level, safe));
    final sink = _sink;
    if (sink != null) {
      try {
        sink.writeln('${_stamp(at)} $level $safe');
      } catch (_) {
        // 磁盘满 / 文件被删：日志失败不影响业务。
      }
    }
  }

  static String _stamp(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 敏感信息兜底遮蔽（key / token 形态）。
  static String redact(String input) {
    var out = input;
    out = out.replaceAllMapped(
      RegExp(r'(sk-[A-Za-z0-9]{4})[A-Za-z0-9\-_]{4,}'),
      (m) => '${m.group(1)}****',
    );
    out = out.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9\-_.]{8,}'),
      (m) => 'Bearer ****',
    );
    out = out.replaceAllMapped(
      RegExp(r'"token"\s*:\s*"([A-Za-z0-9]{4})[A-Za-z0-9]+"'),
      (m) => '"token":"${m.group(1)}****"',
    );
    return out;
  }

  List<String> export() {
    return _entries
        .map((e) => '${_stamp(e.$1)} ${e.$2} ${e.$3}')
        .toList();
  }

  void clear() => _entries.clear();
}
