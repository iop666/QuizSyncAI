import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart' show kMultiPageLimitKey;
import 'package:quizsync_ui/quizsync_ui.dart';

/// 记下写了多少次盘的 KV 存储。
class _CountingStore implements KeyValueStore {
  final Map<String, String> map = {};
  int writes = 0;

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    map[key] = value;
  }
}

/// M47：设置对象有 32 个字段，原来每改一项都要把 32 条键**依次写一遍磁盘**
/// （都是串行 await）。现在只写变化过的键。
void main() {
  test('改一项设置只写变化过的键；写下去的值照样能读回来', () async {
    final store = _CountingStore();
    final controller = SettingsController(store);
    await controller.load();

    // 第一次更新会把「库里还没有的键」补齐（默认值落库），这是预期的。
    await controller.updateApp(controller.app.copyWith(multiPageLimit: 3));
    final baseline = store.writes;

    // 第二次只改一项 → 只应写一条。
    await controller.updateApp(controller.app.copyWith(multiPageLimit: 4));
    expect(store.writes - baseline, 1, reason: '只改了一项却写了多条键');
    expect(store.map[kMultiPageLimitKey], '4');

    // 值没变时一条都不写。
    await controller.updateApp(controller.app.copyWith(multiPageLimit: 4));
    expect(store.writes - baseline, 1);

    // 重新加载仍然是最后一次写入的值（同源）。
    final reloaded = SettingsController(store);
    await reloaded.load();
    expect(reloaded.app.multiPageLimit, 4);
  });
}
