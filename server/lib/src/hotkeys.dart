/// 全局热键的**纯逻辑**层：文本 ↔ (修饰键, 虚拟键码) ↔ 规范标签。
///
/// 参考主项目 `apps/desktop/lib/services/hotkeys.dart` 的键表与标签规则，但
/// Server 是 CLI：没有 Flutter 的 `LogicalKeyboardKey` / `hotkey_manager`，
/// 用户直接用文本输入（`Ctrl+Shift+Q`、`F6`），所以这里自带一份解析器与键表。
///
/// 本文件不碰 FFI、不碰窗口，可被单测直接驱动。
library;

/// 修饰键位（与 win32 的 MOD_* 完全一致）。
const int kModAlt = 0x0001;
const int kModControl = 0x0002;
const int kModShift = 0x0004;
const int kModWin = 0x0008;

/// 热键动作（**只有两个**，每个动作一条键；用户明确不要备用键）。
enum HotkeySlot {
  capture('截屏识别', '截一张屏立刻识别；多页模式下按它则结束多页并上传已抓的所有图'),
  multipage('多页模式', '第一次按进入多页并抓第一张，继续按追加，攒满 6 张自动上传识别');

  const HotkeySlot(this.title, this.description);

  /// 状态里显示的名字（`截屏识别 : F8`）。
  final String title;
  final String description;

  /// 配置 / 命令里的槽位名。
  String get key => name;
}

/// 用户输入不合法时抛它；[message] 直接给用户看。
class HotkeyFormatException implements Exception {
  final String message;
  const HotkeyFormatException(this.message);

  @override
  String toString() => message;
}

/// 一个可注册的全局热键。
class HotkeySpec {
  /// MOD_* 位组合；0 = 不带修饰键（默认的 F6/F8/F9 就是这样）。
  final int modifiers;
  final int vk;

  const HotkeySpec(this.modifiers, this.vk);

  /// 规范标签，如 `Ctrl+Shift+Q` / `F6`。
  String get label => hotkeyLabel(modifiers, vk);

  /// 是否与另一个组合键冲突（RegisterHotKey 语义：修饰键与主键都相同）。
  bool conflictsWith(HotkeySpec other) =>
      vk == other.vk && modifiers == other.modifiers;

  /// 不带修饰键的字母/数字键会抢走全局输入，CLI 需要提示（但不拒绝）。
  bool get isRiskyBareKey =>
      modifiers == 0 && !(vk >= 0x70 && vk <= 0x7b);

  HotkeySpec copyWith({int? modifiers, int? vk}) =>
      HotkeySpec(modifiers ?? this.modifiers, vk ?? this.vk);

  @override
  String toString() => label;
}

/// 注册失败时给用户的**可操作**提示（纯函数，便于单测）。
///
/// 只在注册失败后调用一次：光说「失败」没用，用户要知道「那我用哪个」。
String hotkeyFreeKeysHint(List<String> freeKeys) => freeKeys.isEmpty
    ? '[Hotkey] 本机 F1–F12 现在都被占用，请改用带修饰键的组合（如 Alt+Shift+Q）'
    : '[Hotkey] 本机现在空闲的键：${freeKeys.join(' ')}'
        '（已被别的程序占用的不会出现在这里，可用 hotkey 命令改成其中之一）';

/// 一个动作当前生效的热键文案（状态行用）。
///
/// [active] 为 null 表示没注册上（被别的程序占用等），要如实说「未生效」。
String hotkeyActionLabel({required String wanted, required String? active}) =>
    active ?? '$wanted(未生效)';

/// 解析用户输入的组合键文本。
///
/// 接受：`F6`、`Ctrl+F6`、`Alt+Q`、`Ctrl + Shift + Q`、`win+shift+f7`、
/// `ctrl+alt+shift+win+a` …（大小写不敏感，`+` 两侧空格随意）。
///
/// 拒绝（给出可读原因）：空、只有修饰键、不认识的键名、重复的修饰键。
HotkeySpec parseHotkey(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const HotkeyFormatException('热键不能为空，例如 F6 或 Ctrl+Shift+Q');
  }
  final parts = trimmed
      .split('+')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    throw const HotkeyFormatException('热键不能为空，例如 F6 或 Ctrl+Shift+Q');
  }

  var modifiers = 0;
  for (var i = 0; i < parts.length; i++) {
    final token = parts[i];
    final mod = _modifierOf(token);
    if (mod != null) {
      if (i == parts.length - 1) {
        throw const HotkeyFormatException('只按修饰键不算组合键，最后还要有一个主键');
      }
      if (modifiers & mod != 0) {
        throw HotkeyFormatException('修饰键重复了：$token');
      }
      modifiers |= mod;
      continue;
    }
    if (i != parts.length - 1) {
      // 中间出现了不是修饰键的键名 → 只能是写错了。
      throw HotkeyFormatException('看不懂的组合键：「$token」。格式如 Ctrl+Shift+Q 或 F6');
    }
    final vk = vkOfName(token);
    if (vk == null) {
      throw HotkeyFormatException('不支持的按键：「$token」（可用 F1–F12、A–Z、0–9、'
          '方向键、Delete 等，详见 help）');
    }
    return HotkeySpec(modifiers, vk);
  }
  throw const HotkeyFormatException('只按修饰键不算组合键，最后还要有一个主键');
}

int? _modifierOf(String token) => switch (token.toLowerCase()) {
      'ctrl' || 'control' || 'ctl' => kModControl,
      'alt' => kModAlt,
      'shift' => kModShift,
      'win' || 'windows' || 'super' || 'meta' || 'cmd' => kModWin,
      _ => null,
    };

/// 键名 → Win32 虚拟键码（VK）。不认识返回 null。
int? vkOfName(String name) {
  final raw = name.trim();
  if (raw.isEmpty) return null;
  if (raw.length == 1) {
    final c = raw.toUpperCase().codeUnitAt(0);
    if (c >= 0x41 && c <= 0x5A) return c; // A–Z
    if (c >= 0x30 && c <= 0x39) return c; // 0–9
  }
  final upper = raw.toUpperCase();
  if (upper.startsWith('F') && upper.length <= 3) {
    final n = int.tryParse(upper.substring(1));
    if (n != null && n >= 1 && n <= 12) return 0x70 + n - 1; // F1–F12
  }
  return _vkByName[upper] ?? _vkByPunctuation[raw];
}

/// 单字符标点（用户直接敲 `Ctrl+-` / `Ctrl+/` 这种写法）。
const Map<String, int> _vkByPunctuation = {
  '-': 0xBD, '=': 0xBB, '[': 0xDB, ']': 0xDD, '\\': 0xDC,
  ';': 0xBA, "'": 0xDE, '`': 0xC0, ',': 0xBC, '.': 0xBE, '/': 0xBF,
};

const Map<String, int> _vkByName = {
  'SPACE': 0x20, 'SPACEBAR': 0x20,
  'ENTER': 0x0D, 'RETURN': 0x0D,
  'TAB': 0x09,
  'ESC': 0x1B, 'ESCAPE': 0x1B,
  'BACKSPACE': 0x08, 'BKSP': 0x08,
  'INSERT': 0x2D, 'INS': 0x2D,
  'DELETE': 0x2E, 'DEL': 0x2E,
  'HOME': 0x24, 'END': 0x23,
  'PAGEUP': 0x21, 'PGUP': 0x21,
  'PAGEDOWN': 0x22, 'PGDN': 0x22,
  'UP': 0x26, 'DOWN': 0x28, 'LEFT': 0x25, 'RIGHT': 0x27,
  'CAPSLOCK': 0x14,
  'MINUS': 0xBD, 'EQUAL': 0xBB, 'EQUALS': 0xBB,
  'COMMA': 0xBC, 'PERIOD': 0xBE, 'SLASH': 0xBF,
  'SEMICOLON': 0xBA, 'QUOTE': 0xDE, 'BACKQUOTE': 0xC0,
  'BRACKETLEFT': 0xDB, 'BRACKETRIGHT': 0xDD, 'BACKSLASH': 0xDC,
};

/// VK → 人读键名（标签里的主键部分）。
String vkLabel(int vk) {
  if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
  if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk);
  if (vk >= 0x70 && vk <= 0x7B) return 'F${vk - 0x70 + 1}';
  for (final entry in _vkByName.entries) {
    if (entry.value == vk) return entry.key;
  }
  return 'VK_0x${vk.toRadixString(16).toUpperCase()}';
}

/// (修饰键, VK) → 规范标签：固定顺序 `Ctrl+Alt+Shift+Win+键`。
String hotkeyLabel(int modifiers, int vk) {
  final mods = <String>[
    if (modifiers & kModControl != 0) 'Ctrl',
    if (modifiers & kModAlt != 0) 'Alt',
    if (modifiers & kModShift != 0) 'Shift',
    if (modifiers & kModWin != 0) 'Win',
  ];
  final key = vkLabel(vk);
  return mods.isEmpty ? key : '${mods.join('+')}+$key';
}
