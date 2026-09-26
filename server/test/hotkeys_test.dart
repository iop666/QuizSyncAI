import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/hotkeys.dart';
import 'package:test/test.dart';

void main() {
  group('parseHotkey', () {
    test('默认热键：F8（截屏识别）、F9（多页模式），只有两条', () {
      // 用户明确「备用热键功能删除，没用」→ 一个动作只留一条键。
      expect(ServerConfig.kDefaultHotkeyCapture, 'F8');
      expect(ServerConfig.kDefaultHotkeyMultipage, 'F9');

      final defaults = ServerConfig();
      expect(defaults.hotkeyCapture, 'F8');
      expect(defaults.hotkeyMultipage, 'F9');

      final capture = parseHotkey(defaults.hotkeyCapture);
      expect(capture.modifiers, 0);
      expect(capture.vk, 0x77); // F8
      expect(capture.label, 'F8');
      expect(parseHotkey(defaults.hotkeyMultipage).vk, 0x78); // F9
      expect(capture.conflictsWith(parseHotkey(defaults.hotkeyMultipage)), isFalse);
    });

    test('只有两个动作、两个槽位名（没有备用键槽位）', () {
      expect(HotkeySlot.values.length, 2);
      expect(HotkeySlot.capture.key, 'capture');
      expect(HotkeySlot.multipage.key, 'multipage');
    });

    test('升级迁移：老配置（含备用键/三个动作/历史默认值）都换成 F8 + F9', () {
      // 上一版：主键 + 备用键。
      final withFallback = ServerConfig(
        hotkeyCapture: 'F8',
        hotkeyMultipage: 'F9',
      ).withMigratedHotkeys();
      expect(withFallback.hotkeyCapture, 'F8');
      expect(withFallback.hotkeyMultipage, 'F9');

      // 上一版的备用键默认值本身就是历史默认 → 换成裸 F 键。
      final fallbackValues = ServerConfig(
        hotkeyCapture: 'Alt+Shift+Q',
        hotkeyMultipage: 'Alt+Shift+W',
      ).withMigratedHotkeys();
      expect(fallbackValues.hotkeyCapture, 'F8');
      expect(fallbackValues.hotkeyMultipage, 'F9');

      // 更早的默认值同样换掉。
      final older = ServerConfig(
        hotkeyCapture: 'Ctrl+Q',
        hotkeyMultipage: 'Ctrl+Shift+S',
      ).withMigratedHotkeys();
      expect(older.hotkeyCapture, 'F8');
      expect(older.hotkeyMultipage, 'F9');

      // 用户自己改的键（不在历史默认表里）原样保留。
      final custom = ServerConfig(
        hotkeyCapture: 'Ctrl+Alt+Z',
        hotkeyMultipage: 'Alt+F12',
      ).withMigratedHotkeys();
      expect(custom.hotkeyCapture, 'Ctrl+Alt+Z');
      expect(custom.hotkeyMultipage, 'Alt+F12');
    });

    test('老配置（带已作废的槽位键名）会被识别出来并迁移', () {
      // 三种老形态：三个动作、主+备用、备用键单独存在。
      for (final legacy in [
        {
          'hotkey_capture': 'Ctrl+Q',
          'hotkey_append': 'Ctrl+Shift+A',
          'hotkey_finish': 'Ctrl+Shift+S',
        },
        {
          'hotkey_capture': 'F8',
          'hotkey_capture_fallback': 'Alt+Shift+Q',
          'hotkey_multipage': 'F9',
          'hotkey_multipage_fallback': 'Alt+Shift+W',
        },
      ]) {
        final json = <String, dynamic>{
          'provider': 'openai-compatible',
          'api_key': 'k',
          'model': 'm',
          ...legacy,
        };
        expect(ServerConfig.hadLegacySlots(json), isTrue, reason: '$legacy');
        final migrated = ServerConfig.fromJson(json);
        expect(migrated.hotkeyCapture, 'F8');
        expect(migrated.hotkeyMultipage, 'F9');
      }
      // 新配置不再被判定成老配置，也不会再出现已删除的键。
      final fresh = ServerConfig(apiKey: 'k', model: 'm');
      expect(ServerConfig.hadLegacySlots(fresh.toJson()), isFalse);
      expect(fresh.toJson().containsKey('hotkey_capture_fallback'), isFalse);
      expect(fresh.toJson().containsKey('hotkey_multipage_fallback'), isFalse);
    });

    test('支持需求列出的全部写法', () {
      expect(parseHotkey('Ctrl+F6').label, 'Ctrl+F6');
      expect(parseHotkey('Alt+F6').label, 'Alt+F6');
      expect(parseHotkey('Shift+F6').label, 'Shift+F6');
      expect(parseHotkey('Ctrl+Shift+F6').label, 'Ctrl+Shift+F6');
      expect(parseHotkey('Ctrl+Alt+Q').label, 'Ctrl+Alt+Q');
      expect(parseHotkey('Ctrl+Shift+Q').label, 'Ctrl+Shift+Q');
      expect(parseHotkey('Alt+Q').label, 'Alt+Q');
      // 规范顺序是 Ctrl→Alt→Shift→Win（与主项目一致的固定顺序）。
      expect(parseHotkey('Win+Shift+F7').label, 'Shift+Win+F7');
    });

    test('大小写、空格、修饰键顺序都随意，标签是规范形式', () {
      expect(parseHotkey('ctrl + shift + q').label, 'Ctrl+Shift+Q');
      expect(parseHotkey('SHIFT+CTRL+Q').label, 'Ctrl+Shift+Q');
      expect(parseHotkey('alt+shift+w').label, 'Alt+Shift+W');
    });

    test('F1–F12 与常用键名都认', () {
      for (var i = 1; i <= 12; i++) {
        expect(parseHotkey('F$i').vk, 0x70 + i - 1);
      }
      expect(parseHotkey('Ctrl+Space').vk, 0x20);
      expect(parseHotkey('Ctrl+Delete').vk, 0x2E);
      expect(parseHotkey('Ctrl+PageUp').vk, 0x21);
      expect(parseHotkey('Ctrl+-').vk, 0xBD);
      expect(parseHotkey('Ctrl+0').vk, 0x30);
    });

    test('不合法的输入给出可读原因', () {
      expect(() => parseHotkey(''), throwsA(isA<HotkeyFormatException>()));
      expect(() => parseHotkey('Ctrl+Shift'), throwsA(isA<HotkeyFormatException>()));
      expect(() => parseHotkey('Ctrl+Bogus'), throwsA(isA<HotkeyFormatException>()));
      expect(() => parseHotkey('F13'), throwsA(isA<HotkeyFormatException>()));
      expect(() => parseHotkey('Ctrl+Ctrl+Q'), throwsA(isA<HotkeyFormatException>()));
      expect(
        () => parseHotkey('Ctrl+Q+R'),
        throwsA(isA<HotkeyFormatException>()),
      );
    });
  });

  group('冲突与风险判定', () {
    test('同一组合键才算冲突（修饰键不同不冲突）', () {
      expect(parseHotkey('F8').conflictsWith(parseHotkey('F8')), isTrue);
      expect(parseHotkey('F8').conflictsWith(parseHotkey('Ctrl+F8')), isFalse);
      expect(parseHotkey('Ctrl+Shift+Q').conflictsWith(parseHotkey('Ctrl+Shift+Q')),
          isTrue);
    });

    test('不带修饰键的字母/数字键要提示会抢全局输入，F 键不用', () {
      expect(parseHotkey('Q').isRiskyBareKey, isTrue);
      expect(parseHotkey('5').isRiskyBareKey, isTrue);
      expect(parseHotkey('F8').isRiskyBareKey, isFalse);
      expect(parseHotkey('Ctrl+Q').isRiskyBareKey, isFalse);
    });

    test('注册失败时给出的「本机空闲键」提示', () {
      expect(hotkeyFreeKeysHint(const ['F3', 'F4', 'F6']), contains('F3 F4 F6'));
      expect(hotkeyFreeKeysHint(const ['F3', 'F4']), contains('hotkey'));
      expect(hotkeyFreeKeysHint(const []), contains('Alt+Shift+Q'));
    });

    test('状态里的热键文案：没注册上要说「未生效」', () {
      expect(hotkeyActionLabel(wanted: 'F8', active: 'F8'), 'F8');
      expect(hotkeyActionLabel(wanted: 'F8', active: null), 'F8(未生效)');
    });
  });
}
