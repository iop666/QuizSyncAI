import 'dart:convert';

/// 单个字段的写入时钟：`{"l": lamport, "d": deviceId}`（`data-model.md` 2.2）。
class FieldClock {
  final int l;
  final String d;

  const FieldClock(this.l, this.d);

  Map<String, dynamic> toJson() => {'l': l, 'd': d};

  factory FieldClock.fromJson(Map<String, dynamic> json) =>
      FieldClock((json['l'] as num).toInt(), json['d'].toString());

  @override
  bool operator ==(Object other) => other is FieldClock && other.l == l && other.d == d;

  @override
  int get hashCode => Object.hash(l, d);

  @override
  String toString() => 'FieldClock(l=$l, d=$d)';
}

/// 版本比较：先比 lamport，相同则比 device_id 字典序。返回 -1 / 0 / 1。
int compareVersions(int l1, String d1, int l2, String d2) {
  if (l1 != l2) return l1 < l2 ? -1 : 1;
  final c = d1.compareTo(d2);
  return c == 0 ? 0 : (c < 0 ? -1 : 1);
}

Map<String, FieldClock> parseFieldClocks(dynamic raw) {
  if (raw is Map) {
    return raw.map((k, v) {
      if (v is Map) {
        return MapEntry(k.toString(), FieldClock.fromJson(Map<String, dynamic>.from(v)));
      }
      return MapEntry(k.toString(), const FieldClock(0, ''));
    });
  }
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return parseFieldClocks(decoded);
    } catch (_) {
      // 容错：损坏的 clock 串按空处理。
    }
  }
  return {};
}

String fieldClocksToJson(Map<String, FieldClock> clocks) =>
    jsonEncode(clocks.map((k, v) => MapEntry(k, v.toJson())));
