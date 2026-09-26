import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/option.dart';
import '../sync/field_clocks.dart';

/// `options_json` ↔ `List<Option>`。
class OptionsListConverter extends TypeConverter<List<Option>, String?> {
  const OptionsListConverter();

  @override
  List<Option> fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return const [];
    final raw = jsonDecode(fromDb);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => Option.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  }

  @override
  String? toSql(List<Option> value) =>
      jsonEncode(value.map((o) => o.toJson()).toList());
}

/// `choice_json` / `warnings_json` ↔ `List<String>`。
class StringListConverter extends TypeConverter<List<String>, String?> {
  const StringListConverter();

  @override
  List<String> fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return const [];
    final raw = jsonDecode(fromDb);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  @override
  String? toSql(List<String> value) => jsonEncode(value);
}

/// `field_clocks_json` ↔ `Map<String, FieldClock>`。
class FieldClocksConverter
    extends TypeConverter<Map<String, FieldClock>, String?> {
  const FieldClocksConverter();

  @override
  Map<String, FieldClock> fromSql(String? fromDb) =>
      fromDb == null ? {} : parseFieldClocks(fromDb);

  @override
  String? toSql(Map<String, FieldClock> value) => fieldClocksToJson(value);
}
