import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

void main() {
  group('Lamport 时钟（data-model.md 2.1）', () {
    test('本地写入单调递增', () {
      final c = LamportClock();
      expect(c.tick(), 1);
      expect(c.tick(), 2);
      expect(c.tick(), 3);
      expect(c.value, 3);
    });

    test('收到较大 lamport 后本地时钟被推高（max+1）', () {
      final c = LamportClock();
      c.tick(); // 1
      c.tick(); // 2
      c.observe(10);
      expect(c.value, 11);
      expect(c.tick(), 12);
    });

    test('收到较小 lamport 不影响单调性', () {
      final c = LamportClock();
      c.tick(); // 1
      c.tick(); // 2
      c.observe(1);
      expect(c.value, 3);
    });

    test('restore 只升不降', () {
      final c = LamportClock(5);
      c.restore(3);
      expect(c.value, 5);
      c.restore(9);
      expect(c.value, 9);
    });
  });

  group('版本比较（lamport 优先，device_id 字典序决胜）', () {
    test('lamport 大者胜', () {
      expect(compareVersions(5, 'aaa', 4, 'zzz'), 1);
      expect(compareVersions(4, 'zzz', 5, 'aaa'), -1);
    });

    test('lamport 相同时按 device_id 字典序', () {
      expect(compareVersions(5, 'aaa', 5, 'bbb'), -1);
      expect(compareVersions(5, 'bbb', 5, 'aaa'), 1);
      expect(compareVersions(5, 'same', 5, 'same'), 0);
    });
  });
}
