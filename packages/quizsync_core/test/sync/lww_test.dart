import 'package:test/test.dart';

import 'package:quizsync_core/model/sync_op.dart';
import 'package:quizsync_core/sync/field_clocks.dart';
import 'package:quizsync_core/sync/lww_applier.dart';

SyncOp op(
  int lamport,
  String device,
  Map<String, dynamic> fields, {
  String opType = 'upsert',
}) =>
    SyncOp(
      opId: 'op-$lamport-$device',
      deviceId: device,
      lamport: lamport,
      entity: SyncEntity.question,
      entityId: 'q1',
      opType: SyncOpType.parse(opType),
      fields: fields,
      createdAt: lamport * 1000,
    );

void main() {
  group('字段级 LWW（data-model.md 2.2 / 2.9 场景 1、2）', () {
    test('同一字段：版本大者胜，与到达顺序无关', () {
      // 先 A 后 B
      final rowA = <String, dynamic>{
        'stem': 'A 的题干',
        'lamport': 10,
        'updated_by': 'dev-a',
      };
      final r1 = LwwApplier.apply(
          currentRow: rowA, clocks: {'stem': const FieldClock(10, 'dev-a')}, op: op(12, 'dev-b', {'stem': 'B 的题干'}));
      expect(rowA['stem'], 'B 的题干');
      expect(r1.appliedFields, {'stem'});

      // 先 B 后 A
      final rowB = <String, dynamic>{
        'stem': 'B 的题干',
        'lamport': 12,
        'updated_by': 'dev-b',
      };
      final r2 = LwwApplier.apply(
          currentRow: rowB, clocks: {'stem': const FieldClock(12, 'dev-b')}, op: op(10, 'dev-a', {'stem': 'A 的题干'}));
      expect(rowB['stem'], 'B 的题干');
      expect(r2.appliedFields, isEmpty);
    });

    test('不同字段：两个改动都保留', () {
      final row = <String, dynamic>{
        'stem': '原题干',
        'analysis': '原解析',
        'lamport': 5,
        'updated_by': 'dev-a',
      };
      final clocks = {
        'stem': const FieldClock(5, 'dev-a'),
        'analysis': const FieldClock(5, 'dev-a'),
      };
      // dev-b 改 stem
      LwwApplier.apply(
          currentRow: row, clocks: clocks, op: op(7, 'dev-b', {'stem': '新题干'}));
      // dev-c 改 analysis
      final r = LwwApplier.apply(
          currentRow: row, clocks: clocks, op: op(9, 'dev-c', {'analysis': '新解析'}));
      expect(row['stem'], '新题干');
      expect(row['analysis'], '新解析');
      expect(r.appliedFields, {'analysis'});
      expect(r.rowLamport, 9);
      expect(r.rowUpdatedBy, 'dev-c');
    });

    test('字段时钟缺失时以行级 lamport 为基准比较', () {
      // 行整体写入于 (8, dev-a)，无字段时钟；op (7) 更旧 → 跳过
      final row = <String, dynamic>{
        'stem': '整体写入',
        'lamport': 8,
        'updated_by': 'dev-a',
      };
      var r = LwwApplier.apply(
          currentRow: row, clocks: {}, op: op(7, 'dev-b', {'stem': '旧改动'}));
      expect(r.appliedFields, isEmpty);
      expect(row['stem'], '整体写入');

      // op (9) 更新 → 应用
      r = LwwApplier.apply(
          currentRow: row, clocks: r.clocks, op: op(9, 'dev-b', {'stem': '新改动'}));
      expect(r.appliedFields, {'stem'});
      expect(row['stem'], '新改动');
    });

    test('lamport 相同 → device_id 字典序大者胜', () {
      final row = <String, dynamic>{
        'stem': 'a 的值',
        'lamport': 6,
        'updated_by': 'dev-a',
      };
      final r = LwwApplier.apply(
          currentRow: row,
          clocks: {'stem': const FieldClock(6, 'dev-a')},
          op: op(6, 'dev-b', {'stem': 'b 的值'}));
      expect(r.appliedFields, {'stem'});
      expect(row['stem'], 'b 的值');
    });

    test('删除（tombstone）按同一时间戳规则决胜（2.9 场景 4）', () {
      // 行已有 (10, dev-a) 的字段写入；更晚的 delete (11) 生效
      final row = <String, dynamic>{
        'stem': '还在',
        'deleted_at': null,
        'lamport': 10,
        'updated_by': 'dev-a',
      };
      var r = LwwApplier.apply(
          currentRow: row,
          clocks: {'stem': const FieldClock(10, 'dev-a')},
          op: op(11, 'dev-a', {'deleted_at': 999}, opType: 'delete'));
      expect(r.appliedFields, {'deleted_at'});
      expect(row['deleted_at'], 999);

      // 更早的 delete (8) 不生效
      final row2 = <String, dynamic>{
        'stem': '还在',
        'deleted_at': null,
        'lamport': 10,
        'updated_by': 'dev-a',
      };
      r = LwwApplier.apply(
          currentRow: row2,
          clocks: {'stem': const FieldClock(10, 'dev-a')},
          op: op(8, 'dev-a', {'deleted_at': 777}, opType: 'delete'));
      expect(r.appliedFields, isEmpty);
      expect(row2['deleted_at'], isNull);
    });
  });
}
