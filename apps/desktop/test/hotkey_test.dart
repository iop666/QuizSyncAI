import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:quizsync_desktop/services/hotkeys.dart';

/// 热键模块重写（用户反馈 6）的回归测试。
///
/// 最重要的一条：`HotKeyRecorder` 录出来的 `HotKey` 里是**物理键**
/// （PhysicalKeyboardKey），原实现只认 LogicalKeyboardKey → 用户自定义的
/// 快捷键 100% 被判成「不支持」并静默回退，表现就是「设置了不生效」。
void main() {
  /// 假注册器：[taken] 里的组合键视为被其他程序占用。
  final fake = _FakeRegistrar();

  setUp(fake.reset);

  group('键位映射', () {
    test('录制出来的物理键能转成 VK 与标签（回归：原来一律判成不支持）', () {
      final recorded = HotKey(
        key: PhysicalKeyboardKey.keyA,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      expect(vkOfKey(recorded.key), 0x41);
      expect(hotkeyLabelOf(recorded), 'Ctrl+Alt+A');
      expect(hotkeyRejectReason(recorded), isNull);
      final binding = bindingOf(recorded, HotkeySlot.capture);
      expect(binding, isNotNull);
      expect(binding!.vk, 0x41);
      expect(binding.nativeModifiers, kModControl | kModAlt);
      expect(binding.label, 'Ctrl+Alt+A');
    });

    test('数字 / 功能键 / 方向键的物理键也能映射', () {
      int vkOf(PhysicalKeyboardKey k, {HotKeyModifier mod = HotKeyModifier.control}) =>
          vkOfKey(HotKey(key: k, modifiers: [mod]).key)!;
      expect(vkOf(PhysicalKeyboardKey.digit1), 0x31);
      expect(vkOf(PhysicalKeyboardKey.f5), 0x74);
      expect(vkOf(PhysicalKeyboardKey.arrowLeft), 0x25);
      expect(vkOfKey(const PhysicalKeyboardKey(0x99)), isNull,
          reason: '表里没有的键要老实返回 null（UI 会提示不支持）');
    });

    test('逻辑键同样支持（老配置里存的就是逻辑键）', () {
      final hk = HotKey(
        key: LogicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      expect(bindingOf(hk, HotkeySlot.capture)!.vk, 0x51);
      expect(hotkeyLabelOf(hk), 'Ctrl+Alt+Q');
    });

    test('修饰键顺序固定：同一个键不因录入顺序不同而显示成两种写法', () {
      final a = HotKey(
          key: PhysicalKeyboardKey.keyS,
          modifiers: [HotKeyModifier.alt, HotKeyModifier.control]);
      final b = HotKey(
          key: PhysicalKeyboardKey.keyS,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt]);
      expect(hotkeyLabelOf(a), 'Ctrl+Alt+S');
      expect(hotkeyLabelOf(a), hotkeyLabelOf(b));
    });

    test('不接受的组合键给出人话原因', () {
      expect(
          hotkeyRejectReason(HotKey(key: PhysicalKeyboardKey.keyA)),
          contains('修饰键'),
          reason: '没有修饰键会把普通打字全抢走');
      expect(
          hotkeyRejectReason(HotKey(
              key: PhysicalKeyboardKey.controlLeft,
              modifiers: [HotKeyModifier.control])),
          contains('只按修饰键'));
      expect(
          hotkeyRejectReason(HotKey(
              key: const PhysicalKeyboardKey(0x99),
              modifiers: [HotKeyModifier.control])),
          contains('不支持'));
    });

    // M46 第 1 条：默认热键就是**单按** F8 / F9，所以功能键必须放行；
    // 而单按字母/数字仍然要被挡掉（会把普通打字全抢走）。
    test('单按 F1–F12 可以作热键，单按字母/数字不行', () {
      for (final key in [PhysicalKeyboardKey.f8, PhysicalKeyboardKey.f9]) {
        expect(hotkeyRejectReason(HotKey(key: key)), isNull,
            reason: '$key 是默认热键，必须放行');
      }
      expect(isFunctionKeyVk(0x77), isTrue, reason: '0x77 = F8');
      expect(isFunctionKeyVk(0x78), isTrue, reason: '0x78 = F9');
      expect(isFunctionKeyVk(0x41), isFalse, reason: '0x41 = A');
      expect(hotkeyRejectReason(HotKey(key: PhysicalKeyboardKey.digit5)),
          contains('修饰键'));
    });
  });

  // M46 第 1 条：两个热键的语义（什么时候单张、什么时候结束多页、什么时候算满）
  // 抽成了纯函数，这里把用户口径逐条钉住。
  group('两个热键的语义（M46 第 1 条）', () {
    test('截屏识别键：没攒页＝单张；攒着页＝结束多页（不再多截一张）', () {
      expect(intentOfCaptureHotkey(0), CaptureIntent.single);
      expect(intentOfCaptureHotkey(1), CaptureIntent.finishMultipage);
      expect(intentOfCaptureHotkey(6), CaptureIntent.finishMultipage);
    });

    test('多页模式键：没满就抓页；已满则不再抓（等截屏识别键上传）', () {
      expect(intentOfMultipageHotkey(staged: 0, limit: 6),
          CaptureIntent.multipagePage,
          reason: '第一下进入多页模式并抓第 1 张');
      expect(intentOfMultipageHotkey(staged: 1, limit: 6),
          CaptureIntent.multipagePage);
      expect(intentOfMultipageHotkey(staged: 5, limit: 6),
          CaptureIntent.multipagePage);
      expect(intentOfMultipageHotkey(staged: 6, limit: 6),
          CaptureIntent.multipageFull);
    });

    test('抓满第 6 张就自动上传识别', () {
      expect(shouldAutoUploadAfterCapture(staged: 5, limit: 6), isFalse);
      expect(shouldAutoUploadAfterCapture(staged: 6, limit: 6), isTrue,
          reason: '用户明确要求：累积到第六张则截取完第六张自动上传识别');
      // 上限被用户调小（1–6）时同样成立。
      expect(shouldAutoUploadAfterCapture(staged: 3, limit: 3), isTrue);
    });
  });

  group('注册编排', () {
    Future<Map<HotkeySlot, HotkeyStatus>> run({
      Map<HotkeySlot, HotkeyCustomRequest> custom = const {},
    }) =>
        registerAllHotkeys(
          registrar: fake,
          handlers: {
            for (final s in HotkeySlot.values) s: () {},
          },
          custom: custom,
        );

    test('默认：两个槽位各自注册到默认键 F8 / F9', () async {
      final statuses = await run();
      expect(statuses[HotkeySlot.capture]!.activeLabel, 'F8');
      expect(statuses[HotkeySlot.multipage]!.activeLabel, 'F9');
      expect(statuses[HotkeySlot.capture]!.outcome, HotkeyOutcome.active);
      expect(statuses[HotkeySlot.capture]!.message, contains('默认热键已生效'));
    });

    test('候选键被占用时自动换下一个（不静默失败）', () async {
      fake.take('F8', 'Ctrl+Alt+Q');
      final statuses = await run();
      expect(statuses[HotkeySlot.capture]!.activeLabel, 'Ctrl+Alt+X');
      expect(statuses[HotkeySlot.capture]!.outcome, HotkeyOutcome.active);
    });

    test('候选键全被占用 → 明确告知走托盘菜单', () async {
      for (final c in kHotkeyCandidates[HotkeySlot.capture]!) {
        fake.take(c.label);
      }
      final statuses = await run();
      final cap = statuses[HotkeySlot.capture]!;
      expect(cap.activeLabel, isNull);
      expect(cap.ok, isFalse);
      expect(cap.outcome, HotkeyOutcome.noCandidate);
      expect(cap.message, contains('托盘菜单'));
      expect(statuses[HotkeySlot.multipage]!.activeLabel, 'F9',
          reason: '一个槽位失败不影响别的槽位');
    });

    test('自定义热键生效时就是它（物理键录入）', () async {
      final hk = HotKey(
        key: PhysicalKeyboardKey.f7,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      final statuses = await run(custom: {
        HotkeySlot.capture: HotkeyCustomRequest.of(hk, HotkeySlot.capture),
      });
      final cap = statuses[HotkeySlot.capture]!;
      expect(cap.activeLabel, 'Ctrl+Alt+F7');
      expect(cap.customLabel, 'Ctrl+Alt+F7');
      expect(cap.outcome, HotkeyOutcome.active);
      expect(cap.message, contains('自定义热键已生效'));
    });

    test('自定义键被占用 → 回退并如实记录原因（不再静默）', () async {
      final hk = HotKey(
        key: PhysicalKeyboardKey.f7,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );
      fake.take('Ctrl+Alt+F7');
      final statuses = await run(custom: {
        HotkeySlot.capture: HotkeyCustomRequest.of(hk, HotkeySlot.capture),
      });
      final cap = statuses[HotkeySlot.capture]!;
      expect(cap.activeLabel, 'F8', reason: '回退到默认键');
      expect(cap.customLabel, 'Ctrl+Alt+F7');
      expect(cap.outcome, HotkeyOutcome.customTaken);
      expect(cap.message, contains('已被其他程序占用'));
      expect(cap.outcome.isFallback, isTrue);
    });

    test('自定义键本程序不支持 → 回退并说明原因', () async {
      final hk = HotKey(
        key: const PhysicalKeyboardKey(0x99),
        modifiers: [HotKeyModifier.control],
      );
      final statuses = await run(custom: {
        HotkeySlot.capture: HotkeyCustomRequest.of(hk, HotkeySlot.capture),
      });
      final cap = statuses[HotkeySlot.capture]!;
      expect(cap.activeLabel, 'F8');
      expect(cap.outcome, HotkeyOutcome.unsupported);
      expect(cap.customError, contains('不支持'));
    });

    test('两个槽位可以分别自定义，互不干扰（含单按功能键）', () async {
      final statuses = await run(custom: {
        HotkeySlot.capture: HotkeyCustomRequest.of(
            HotKey(key: PhysicalKeyboardKey.f7), HotkeySlot.capture),
        HotkeySlot.multipage: HotkeyCustomRequest.of(
            HotKey(
                key: PhysicalKeyboardKey.f9,
                modifiers: [HotKeyModifier.shift]),
            HotkeySlot.multipage),
      });
      expect(statuses[HotkeySlot.capture]!.activeLabel, 'F7',
          reason: 'M46：单按 F1–F12 是合法的自定义热键');
      expect(statuses[HotkeySlot.multipage]!.activeLabel, 'Shift+F9');
      expect(fake.registered.where((s) => s.startsWith('multipage')).toList(),
          ['multipage:Shift+F9']);
    });

    test('重复注册前先注销旧的（改热键后不会两个键同时生效）', () async {
      await run();
      expect(fake.unregisterCalls, 1);
      await run();
      expect(fake.unregisterCalls, 2);
      expect(fake.registered.length, 2, reason: '重复注册后仍只有两个槽位');
    });
  });

  group('触发闸门（M31：抑制发生在触发那一刻，不会把键锁死）', () {
    test('不传 blocked：原样直通，不多包一层', () {
      void action() {}
      expect(gatedTrigger(action: action), same(action));
    });

    test('blocked 为 false 时照常触发；为 true 时丢弃并报明原因', () {
      var blocked = false;
      final fired = <String>[];
      final logs = <String>[];
      final trigger = gatedTrigger(
        action: () => fired.add('go'),
        blocked: () => blocked,
        label: '截图识别 Ctrl+Alt+X',
        onBlocked: logs.add,
      );

      trigger();
      expect(fired, ['go'], reason: '没被抑制时必须执行真实动作');

      blocked = true;
      trigger();
      expect(fired, ['go'], reason: '被抑制的那一次不许触发截屏');
      expect(logs.single, contains('Ctrl+Alt+X'),
          reason: '被吞掉的触发要写进日志 —— M30 那次排查就卡在「什么都看不出来」');
    });

    // 用户实测（M30 的坑）：进热键页 → `unregister()` 全部热键；而窗口收进托盘 /
    // 最小化时页面不会被卸载，标志一直是 true，于是用户**在任何地方**按都没反应。
    // M31 重写后这两条必须同时成立：
    //   ① 抑制期间键**照旧注册着**（键没丢，离开本页立刻可用）；
    //   ② 抑制期间按下的那一次被丢弃，其它时候照常触发。
    test('抑制期间仍然注册着全部键（这正是 M30 锁死的根因）', () async {
      final reg = _FakeRegistrar();
      final fired = <String>[];
      reg.blocked = true; // 模拟「热键设置页正停在前台」
      final statuses = await registerAllHotkeys(
        registrar: reg,
        handlers: {
          for (final s in HotkeySlot.values) s: () => fired.add(s.name),
        },
        blocked: () => reg.blocked,
      );

      expect(reg.registered.length, 2,
          reason: '「本页在前台」只是忽略触发，不许再把键注销掉');
      expect(reg.unregisterCalls, 1,
          reason: '只有注册前那一次清场，抑制不该额外注销');
      expect(statuses[HotkeySlot.capture]!.activeLabel, 'F8',
          reason: '状态必须真实：键确实注册着，页面显示的也是它');

      reg.triggers['capture']!();
      expect(fired, isEmpty);

      reg.blocked = false; // 离开本页 / 切到别的程序
      reg.triggers['capture']!();
      expect(fired, ['capture']);
    });
  });
}

class _FakeRegistrar implements HotkeyRegistrar {
  final Set<String> _taken = {};
  final List<String> registered = [];

  /// 槽位名 → 注册时拿到的触发回调（M31：要能手动「按一下」验证闸门）。
  final Map<String, void Function()> triggers = {};

  /// 对外暴露给 `blocked: () => reg.blocked`，模拟「热键设置页是否在前台」。
  bool blocked = false;

  int unregisterCalls = 0;

  void reset() {
    _taken.clear();
    registered.clear();
    triggers.clear();
    blocked = false;
    unregisterCalls = 0;
  }

  void take(String first, [String? second, String? third, String? fourth]) {
    for (final l in [first, second, third, fourth]) {
      if (l != null) _taken.add(l);
    }
  }

  @override
  Future<bool> register({
    required String slot,
    required int vk,
    required int nativeModifiers,
    required String label,
    required void Function() onTrigger,
  }) async {
    if (_taken.contains(label)) return false;
    registered.add('$slot:$label');
    triggers[slot] = onTrigger;
    return true;
  }

  @override
  Future<void> unregister({String? slot}) async {
    unregisterCalls++;
    registered.clear();
    triggers.clear();
  }
}
