import 'dart:math';

/// UUID v4（协议里 task_id / op_id / device_id 都用它）。
String newUuidV4() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-'
      '${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-'
      '${h.substring(20)}';
}

/// UTC 毫秒时间戳（协议统一 `*_at`，int64）。
int nowMs() => DateTime.now().millisecondsSinceEpoch;
