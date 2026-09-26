import 'package:flutter/services.dart'
    show KeyboardKey, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';

/// 全局热键的**纯逻辑**层（用户反馈 6：重写热键模块）。
///
/// 这里不碰 isolate、不碰窗口，只做三件事：
///   1. 键 → Win32 虚拟键码（VK）的映射（逻辑键与**物理键**都要认）；
///   2. 组合键标签（Ctrl+Alt+Q 这种）；
///   3. 每个槽位的候选键与注册编排（可注入假注册器做单测）。
///
/// 原实现的致命 bug：录制出来的 `HotKey` 里是 `PhysicalKeyboardKey`，而
/// `_setupHotkey` 只认 `LogicalKeyboardKey` → 用户自定义的快捷键一律被判成
/// 「不支持」并悄悄回退到默认候选键（表现就是「热键设置了不生效」）。
///
/// ## M46 第 1 条：热键只留**两个**，默认 F8 / F9
///
/// 用户要求「只有两个热键，默认截屏识别为 F8；进入多页模式并截取第一张为 F9」，
/// 并明确「截屏逻辑和 server 类似」—— 服务端（`server/lib/src/capture_flow.dart`）
/// 就是这两个动作的语义，这里把它搬到桌面端：
///   * **截屏识别（F8）**：不在多页模式 → 截一张立刻识别；已在多页模式 → **结束多页**，
///     把已抓的图一起上传识别（**不再多截一张**）；
///   * **多页模式（F9）**：第一下进入多页并抓第 1 张，继续按追加；抓满上限
///     （默认 6 张）**自动上传识别**。
/// 原来的「添加页面 / 结束多页识别」两条热键合并成上面这一条多页热键。

// ---------------------------------------------------------------------------
// 修饰键（与 win32 的 MOD_* 一致，这里自带常量以便纯逻辑可单测）
// ---------------------------------------------------------------------------

const int kModAlt = 0x0001;
const int kModControl = 0x0002;
const int kModShift = 0x0004;
const int kModWin = 0x0008;

/// 热键用途。每个槽位各自注册、互不影响（RegisterHotKey 的 id 是线程级的）。
///
/// M46 第 1 条：**只有两个**（用户要求「就是只有两个热键」）。
enum HotkeySlot {
  capture('截屏识别', '截取鼠标所在的那块屏幕立刻识别；已在多页模式里时＝结束多页并上传已抓的图'),
  multipage('多页模式', '按第一下进入多页并抓第一张，继续按追加；抓满 6 张自动上传识别');

  const HotkeySlot(this.title, this.description);

  final String title;
  final String description;

  /// 托盘菜单里的动作 key（与 main.dart 的菜单项一致）。
  String get trayAction => switch (this) {
        HotkeySlot.capture => 'capture',
        HotkeySlot.multipage => 'multipage',
      };
}

/// 一次热键触发该做什么（M46 第 1 条）。
///
/// 抽成纯函数是为了**能单测**：这几条语义（什么时候单张、什么时候结束多页、
/// 什么时候算满）就是这个里程碑的核心逻辑，不能只写在窗口回调里。
enum CaptureIntent {
  /// 截一张屏立刻识别。
  single,

  /// 结束多页：把已攒的页一次上传识别（**不再多截一张**）。
  finishMultipage,

  /// 截一张并把这一页并入多页暂存区。
  multipagePage,

  /// 多页暂存已满：不再截，等用户按截屏识别键上传（或按 UI 上的「结束」）。
  multipageFull,
}

/// 「截屏识别」热键按一下该做什么：[staged] = 当前已暂存几页。
///
/// 攒着页就说明用户正在多页模式里 → 这一按是**结束多页**（服务端同样是这个语义）。
CaptureIntent intentOfCaptureHotkey(int staged) =>
    staged > 0 ? CaptureIntent.finishMultipage : CaptureIntent.single;

/// 「多页模式」热键按一下该做什么：[staged] 已暂存页数、[limit] 本次上限。
CaptureIntent intentOfMultipageHotkey({
  required int staged,
  required int limit,
}) =>
    staged >= limit ? CaptureIntent.multipageFull : CaptureIntent.multipagePage;

/// 抓完一张之后要不要**立刻自动上传识别**（用户要求：抓满第 6 张就自动识别）。
bool shouldAutoUploadAfterCapture({
  required int staged,
  required int limit,
}) =>
    staged >= limit;

/// 某个槽位的注册结果类型（决定设置页怎么显示）。
enum HotkeyOutcome {
  /// 用上了（自定义或候选键）。
  active,

  /// 自定义键被其他程序占用 → 已自动回退到候选键。
  customTaken,

  /// 自定义键本程序不认识（如 Fn、单手修饰键） → 已自动回退。
  unsupported,

  /// 候选键全部被占用：只能走托盘菜单。
  noCandidate;

  bool get isFallback =>
      this == HotkeyOutcome.customTaken || this == HotkeyOutcome.unsupported;
}

/// 一个槽位当前的完整热键状态（设置页与托盘提示都读它）。
class HotkeyStatus {
  final HotkeySlot slot;

  /// 实际生效的组合键标签；null = 没注册上。
  final String? activeLabel;

  /// 用户自定义的组合键标签（没设置过则为 null）。
  final String? customLabel;

  /// 自定义键尝试失败的原因（用于给用户一句明确的话）。
  final String? customError;

  final HotkeyOutcome outcome;

  const HotkeyStatus({
    required this.slot,
    this.activeLabel,
    this.customLabel,
    this.customError,
    this.outcome = HotkeyOutcome.noCandidate,
  });

  bool get ok => activeLabel != null;

  /// 给用户看的一句话说明。
  String get message => switch (outcome) {
        HotkeyOutcome.active =>
          customLabel != null ? '自定义热键已生效' : '默认热键已生效',
        HotkeyOutcome.customTaken =>
          '自定义热键「$customLabel」已被其他程序占用，已自动改用 $activeLabel',
        HotkeyOutcome.unsupported =>
          '自定义热键「$customLabel」暂不支持（${customError ?? '系统不接受该组合'}），已自动改用 $activeLabel',
        HotkeyOutcome.noCandidate =>
          '候选热键都被其他程序占用，请用托盘菜单执行「${slot.title}」',
      };
}

/// 一个可注册的热键绑定。
class HotkeyBinding {
  final HotkeySlot slot;
  final int vk;
  final int nativeModifiers;

  /// 人读标签，例如 `Ctrl+Alt+A`。
  final String label;

  const HotkeyBinding({
    required this.slot,
    required this.vk,
    required this.nativeModifiers,
    required this.label,
  });

  /// 用户自定义时可回写设置页。
  @override
  String toString() => '$label (vk=0x${vk.toRadixString(16)}, mods=$nativeModifiers)';
}

/// 候选键定义（写死在这里，避免 UI 与注册逻辑各写一份）。
class HotkeyCandidate {
  final String label;
  final int vk;
  final int nativeModifiers;
  const HotkeyCandidate(this.label, this.vk, this.nativeModifiers);
}

/// 每个槽位的默认候选键，按优先级排列。
///
/// M46 第 1 条：默认就是 **F8 / F9**（用户明确要求）。单按功能键不会抢走普通
/// 打字，所以可以不带修饰键；但它们也可能被别的程序占用（本机实测老默认键
/// `Ctrl+Alt+Q` 就被小米云服务占着），所以后面仍保留带修饰键的候选键，
/// 注册失败时按顺序往下试（并且把真实生效的键显示在设置页与托盘上）。
const Map<HotkeySlot, List<HotkeyCandidate>> kHotkeyCandidates = {
  HotkeySlot.capture: [
    HotkeyCandidate('F8', 0x77, 0),
    HotkeyCandidate('Ctrl+Alt+Q', 0x51, kModControl | kModAlt),
    HotkeyCandidate('Ctrl+Alt+X', 0x58, kModControl | kModAlt),
    HotkeyCandidate('Ctrl+Shift+Q', 0x51, kModControl | kModShift),
  ],
  HotkeySlot.multipage: [
    HotkeyCandidate('F9', 0x78, 0),
    HotkeyCandidate('Ctrl+Alt+A', 0x41, kModControl | kModAlt),
    HotkeyCandidate('Ctrl+Alt+D', 0x44, kModControl | kModAlt),
    HotkeyCandidate('Ctrl+Shift+A', 0x41, kModControl | kModShift),
  ],
};

// ---------------------------------------------------------------------------
// 键 → VK / 标签
// ---------------------------------------------------------------------------

/// USB HID usage code → Win32 VK（覆盖常用键；字母/数字/F1–F12/标点/导航键）。
const Map<int, int> _vkOfHidUsage = {
  0x04: 0x41, 0x05: 0x42, 0x06: 0x43, 0x07: 0x44, 0x08: 0x45, // A-E
  0x09: 0x46, 0x0a: 0x47, 0x0b: 0x48, 0x0c: 0x49, 0x0d: 0x4a, // F-J
  0x0e: 0x4b, 0x0f: 0x4c, 0x10: 0x4d, 0x11: 0x4e, 0x12: 0x4f, // K-O
  0x13: 0x50, 0x14: 0x51, 0x15: 0x52, 0x16: 0x53, 0x17: 0x54, // P-T
  0x18: 0x55, 0x19: 0x56, 0x1a: 0x57, 0x1b: 0x58, 0x1c: 0x59, // U-Y
  0x1d: 0x5a, // Z
  0x1e: 0x31, 0x1f: 0x32, 0x20: 0x33, 0x21: 0x34, 0x22: 0x35, // 1-5
  0x23: 0x36, 0x24: 0x37, 0x25: 0x38, 0x26: 0x39, 0x27: 0x30, // 6-0
  0x28: 0x0d, 0x29: 0x1b, 0x2a: 0x08, 0x2b: 0x09, 0x2c: 0x20, // Enter/Esc/BS/Tab/Space
  0x2d: 0xbd, 0x2e: 0xbb, 0x2f: 0xdb, 0x30: 0xdd, 0x31: 0xdc, // - = [ ] \
  0x33: 0xba, 0x34: 0xde, 0x35: 0xc0, 0x36: 0xbc, 0x37: 0xbe, // ; ' ` , .
  0x38: 0xbf, // /
  0x39: 0x14, // CapsLock
  0x3a: 0x70, 0x3b: 0x71, 0x3c: 0x72, 0x3d: 0x73, 0x3e: 0x74, 0x3f: 0x75, // F1-F6
  0x40: 0x76, 0x41: 0x77, 0x42: 0x78, 0x43: 0x79, 0x44: 0x7a, 0x45: 0x7b, // F7-F12
  0x49: 0x2d, 0x4a: 0x24, 0x4b: 0x21, 0x4c: 0x2e, 0x4d: 0x23, 0x4e: 0x22, // Ins/Home/PgUp/Del/End/PgDn
  0x4f: 0x27, 0x50: 0x25, 0x51: 0x28, 0x52: 0x26, // arrows
};

/// 常用 VK 的显示名（字母/数字/F 键由 [vkLabel] 直接算，这里只放其余）。
const Map<int, String> _vkNames = {
  0x08: 'Backspace', 0x09: 'Tab', 0x0d: 'Enter', 0x1b: 'Esc', 0x20: 'Space',
  0x14: 'CapsLock', 0x21: 'PageUp', 0x22: 'PageDown', 0x23: 'End', 0x24: 'Home',
  0x25: 'Left', 0x26: 'Up', 0x27: 'Right', 0x28: 'Down',
  0x2d: 'Insert', 0x2e: 'Delete',
  0xba: ';', 0xbb: '=', 0xbc: ',', 0xbd: '-', 0xbe: '.', 0xbf: '/',
  0xc0: '`', 0xdb: '[', 0xdc: '\\', 0xdd: ']', 0xde: "'",
};

/// Flutter 逻辑键 id → VK。
///
/// 注意：原来的表把 F1–F12 写成 `0x0010000000x`、方向键写成 `0x001000002x`，
/// 都与 Flutter 生成表里的真实 keyId 不符（F1 实际是 `0x00100000801`，
/// 左方向键是 `0x00100000302`）—— 等于这些键从来没映射成功过。这里按生成表更正。
int? vkOfLogicalKey(LogicalKeyboardKey key) {
  final id = key.keyId;
  if (id >= 0x61 && id <= 0x7a) return id - 0x20; // a–z
  if (id >= 0x30 && id <= 0x39) return id; // 0–9
  if (id >= 0x00100000801 && id <= 0x0010000080c) {
    return 0x70 + (id - 0x00100000801); // F1–F12
  }
  const extras = <int, int>{
    0x00100000008: 0x08, // Backspace
    0x00100000009: 0x09, // Tab
    0x0010000000d: 0x0d, // Enter
    0x0010000001b: 0x1b, // Escape
    0x00000000020: 0x20, // Space
    0x00100000104: 0x14, // CapsLock
    0x00100000407: 0x2d, // Insert
    0x0010000007f: 0x2e, // Delete
    0x00100000306: 0x24, // Home
    0x00100000305: 0x23, // End
    0x00100000308: 0x21, // PageUp
    0x00100000307: 0x22, // PageDown
    0x00100000302: 0x25, // ←
    0x00100000304: 0x26, // ↑
    0x00100000303: 0x27, // →
    0x00100000301: 0x28, // ↓
    0x0000000002d: 0xbd, // -
    0x0000000003d: 0xbb, // =
    0x0000000005b: 0xdb, // [
    0x0000000005d: 0xdd, // ]
    0x0000000005c: 0xdc, // \
    0x0000000003b: 0xba, // ;
    0x00000000022: 0xde, // '
    0x00000000060: 0xc0, // `
    0x0000000002c: 0xbc, // ,
    0x0000000002e: 0xbe, // .
    0x0000000002f: 0xbf, // /
  };
  return extras[id];
}

/// 任意键（逻辑键或**物理键**）→ VK。
///
/// 物理键走 USB HID usage 表（与键盘布局无关，也是 RegisterHotKey 要的 VK 语义）。
/// Flutter 的 `usbHidUsage` 把 usage page（0x0007）放在高位，因此取低字节查表。
/// 两者都查不到返回 null（本程序不支持该键）。
int? vkOfKey(KeyboardKey key) {
  if (key is PhysicalKeyboardKey) return _vkOfHidUsage[key.usbHidUsage & 0xff];
  if (key is LogicalKeyboardKey) return vkOfLogicalKey(key);
  return null;
}

/// VK → 人读键名。
String vkLabel(int vk) {
  if (vk >= 0x41 && vk <= 0x5a) return String.fromCharCode(vk); // A–Z
  if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk); // 0–9
  if (vk >= 0x70 && vk <= 0x7b) return 'F${vk - 0x70 + 1}'; // F1–F12
  return _vkNames[vk] ?? 'VK_0x${vk.toRadixString(16).toUpperCase()}';
}

/// 是否功能键 F1–F12。
///
/// M46 第 1 条：默认热键是**单按** F8/F9，所以「必须带修饰键」这条规则要给
/// 功能键开个口子（单按字母/数字确实会抢走普通输入，单按 F1–F12 不会）。
bool isFunctionKeyVk(int vk) => vk >= 0x70 && vk <= 0x7b;

/// 修饰键 → 原生 MOD_* 位。
int nativeModsOf(List<HotKeyModifier>? modifiers) {
  var m = 0;
  for (final mod in modifiers ?? const <HotKeyModifier>[]) {
    switch (mod) {
      case HotKeyModifier.alt:
        m |= kModAlt;
      case HotKeyModifier.control:
        m |= kModControl;
      case HotKeyModifier.shift:
        m |= kModShift;
      case HotKeyModifier.meta:
        m |= kModWin;
      case HotKeyModifier.capsLock:
      case HotKeyModifier.fn:
        break; // RegisterHotKey 不接受它们作修饰键
    }
  }
  return m;
}

/// 修饰键显示名，按固定顺序（Ctrl+Alt+Shift+Win），与录入顺序无关。
const List<HotKeyModifier> _modifierOrder = [
  HotKeyModifier.control,
  HotKeyModifier.alt,
  HotKeyModifier.shift,
  HotKeyModifier.meta,
  HotKeyModifier.capsLock,
  HotKeyModifier.fn,
];

String modifierLabel(HotKeyModifier m) => switch (m) {
      HotKeyModifier.control => 'Ctrl',
      HotKeyModifier.alt => 'Alt',
      HotKeyModifier.shift => 'Shift',
      HotKeyModifier.meta => 'Win',
      HotKeyModifier.capsLock => 'Caps',
      HotKeyModifier.fn => 'Fn',
    };

/// 组合键标签：`Ctrl+Alt+A`。物理键也能给出正确名字（原来会显示成「键」）。
String hotkeyLabelOf(HotKey hk) {
  final vk = vkOfKey(hk.key);
  final keyName = vk == null ? hk.key.keyLabel : vkLabel(vk);
  final mods = <String>[
    for (final m in _modifierOrder)
      if ((hk.modifiers ?? const <HotKeyModifier>[]).contains(m))
        modifierLabel(m),
  ];
  return mods.isEmpty ? keyName : '${mods.join('+')}+$keyName';
}
/// 自定义热键不接受的原因；null = 可用。
///
/// 规则（用户能自己看懂）：
///  - 主键不能是修饰键本身；
///  - 主键必须是本程序认得的键（见 [vkOfKey]）；
///  - 除 F1–F12 外**至少要有一个修饰键**（单按字母/数字会把普通打字全抢走）。
///    M46 第 1 条：默认热键就是单按 F8 / F9，所以功能键放行。
String? hotkeyRejectReason(HotKey hk) {
  final pressedIsModifier = HotKeyModifier.values
      .any((m) => m.physicalKeys.contains(_physicalOf(hk)));
  if (pressedIsModifier) return '只按修饰键不算组合键';
  final vk = vkOfKey(hk.key);
  if (vk == null) return '这个键不支持做全局热键';
  final realMods = (hk.modifiers ?? const <HotKeyModifier>[])
      .where((m) => m == HotKeyModifier.control ||
          m == HotKeyModifier.alt ||
          m == HotKeyModifier.shift ||
          m == HotKeyModifier.meta)
      .toList();
  if (realMods.isEmpty && !isFunctionKeyVk(vk)) {
    return '单按这个键会抢走普通打字，请加一个修饰键（Ctrl / Alt / Shift / Win）；'
        '单按 F1–F12 可以';
  }
  return null;
}

PhysicalKeyboardKey? _physicalOf(HotKey hk) {
  try {
    return hk.physicalKey;
  } catch (_) {
    return null;
  }
}

/// 一组「用户自定义热键」的登记：标签一定给得出来，能不能用看 [binding]。
class HotkeyCustomRequest {
  /// 可注册的绑定；null = 这个组合键本程序用不了（原因见 [rejectReason]）。
  final HotkeyBinding? binding;

  /// 用户设置的那个组合键的标签（即使不可用也要如实显示）。
  final String label;

  final String? rejectReason;

  const HotkeyCustomRequest({
    required this.binding,
    required this.label,
    this.rejectReason,
  });

  /// 从录入结果构造（不可用时 binding 为 null）。
  factory HotkeyCustomRequest.of(HotKey hk, HotkeySlot slot) => HotkeyCustomRequest(
        binding: bindingOf(hk, slot),
        label: hotkeyLabelOf(hk),
        rejectReason: hotkeyRejectReason(hk),
      );
}

/// 录入的 HotKey → 可注册绑定；不可用返回 null（原因见 [hotkeyRejectReason]）。
HotkeyBinding? bindingOf(HotKey hk, HotkeySlot slot) {
  if (hotkeyRejectReason(hk) != null) return null;
  final vk = vkOfKey(hk.key)!;
  return HotkeyBinding(
    slot: slot,
    vk: vk,
    nativeModifiers: nativeModsOf(hk.modifiers),
    label: hotkeyLabelOf(hk),
  );
}

// ---------------------------------------------------------------------------
// 注册编排
// ---------------------------------------------------------------------------

/// 注册器接口：真实实现是后台 isolate 版 [HotkeyService]；单测注入假实现。
abstract class HotkeyRegistrar {
  /// 注册组合键；成功返回 true 并在每次按下时回调 [onTrigger]。
  Future<bool> register({
    required String slot,
    required int vk,
    required int nativeModifiers,
    required String label,
    required void Function() onTrigger,
  });

  Future<void> unregister({String? slot});
}

/// 把一次热键动作包一层「现场闸门」（M31 重写）。
///
/// [blocked] 在**真正触发的那一刻**才被求值，返回 true 就丢弃这一次触发。
///
/// ## 为什么不是「进热键设置页就 `unregister()`」
///
/// M30 的实现是「热键设置页打开 → 注销全部热键；离开页面 → 重新注册」，前提是
/// **页面一定会被卸载**。实测这个前提不成立（用户报「只有在点进那个页面时不会
/// 触发，其它地方都得能用」）：窗口收进托盘 / 窗口最小化 / 页面还挂在树上时页面
/// 不会被 dispose，于是 `hotkeysSuspendedProvider` 一直是 true —— M30 又把暂停
/// 做成了「权威」（暂停期间连重新注册都被跳过），热键就被**永久**锁死，用户在
/// 页面上看不出异常（那里本来就不该触发），换到别的程序里按同样毫无反应。
///
/// 现在改成：**热键始终注册着**，只在触发时问一句「现在要不要吞掉」。判断依据是
/// 当下的窗口状态（页面是否挂载 + 本窗口是否前台），不依赖任何「进/出页面」的书签，
/// 结构上不可能锁死；被吞掉的触发会写日志，排查时看得见。
void Function() gatedTrigger({
  required void Function() action,
  bool Function()? blocked,
  String label = '',
  void Function(String message)? onBlocked,
}) {
  if (blocked == null) return action;
  return () {
    if (blocked()) {
      onBlocked?.call('热键设置页正在前台：忽略本次「$label」触发（离开本页即恢复）');
      return;
    }
    action();
  };
}

/// 一次性注册全部槽位，返回每个槽位的真实状态。
///
/// 自定义键优先；被占用/不支持时**明确记录原因并回退到候选键**，
/// 不再像原来那样静默回退（用户看不到自己设的键为什么没生效）。
///
/// [blocked]/[onBlocked] 见 [gatedTrigger]：注册本身**永远**执行，抑制发生在触发时。
Future<Map<HotkeySlot, HotkeyStatus>> registerAllHotkeys({
  required HotkeyRegistrar registrar,
  required Map<HotkeySlot, void Function()> handlers,
  Map<HotkeySlot, HotkeyCustomRequest> custom = const {},
  StringSink? log,
  bool Function()? blocked,
  void Function(String message)? onBlocked,
}) async {
  await registrar.unregister();
  final result = <HotkeySlot, HotkeyStatus>{};

  for (final slot in HotkeySlot.values) {
    final handle = handlers[slot];
    if (handle == null) continue;
    final request = custom[slot];
    String? customError;
    String? active;

    if (request != null) {
      final binding = request.binding;
      if (binding == null) {
        customError = request.rejectReason ?? '这个组合键不可用';
        log?.writeln('custom[${slot.name}] ${request.label} rejected: $customError');
      } else {
        final ok = await registrar.register(
          slot: slot.name,
          vk: binding.vk,
          nativeModifiers: binding.nativeModifiers,
          label: binding.label,
          onTrigger: gatedTrigger(
            action: handle,
            blocked: blocked,
            label: '${slot.title} ${binding.label}',
            onBlocked: onBlocked,
          ),
        );
        log?.writeln('custom[${slot.name}] ${binding.label} -> $ok');
        if (ok) {
          active = binding.label;
        } else {
          customError = '被其他程序占用';
        }
      }
    }

    if (active == null) {
      for (final c in kHotkeyCandidates[slot] ?? const <HotkeyCandidate>[]) {
        // 同一个组合键不要重复注册（自定义键与候选键撞车时直接跳过）。
        if (request?.binding?.label == c.label) continue;
        final ok = await registrar.register(
          slot: slot.name,
          vk: c.vk,
          nativeModifiers: c.nativeModifiers,
          label: c.label,
          onTrigger: gatedTrigger(
            action: handle,
            blocked: blocked,
            label: '${slot.title} ${c.label}',
            onBlocked: onBlocked,
          ),
        );
        log?.writeln('probe[${slot.name}] ${c.label} -> $ok');
        if (ok) {
          active = c.label;
          break;
        }
      }
    }

    final HotkeyOutcome outcome;
    if (request == null) {
      outcome = active == null
          ? HotkeyOutcome.noCandidate
          : HotkeyOutcome.active;
    } else if (active == null) {
      outcome = HotkeyOutcome.noCandidate;
    } else if (active == request.binding?.label) {
      outcome = HotkeyOutcome.active;
    } else if (request.binding == null) {
      outcome = HotkeyOutcome.unsupported;
    } else {
      outcome = HotkeyOutcome.customTaken;
    }

    result[slot] = HotkeyStatus(
      slot: slot,
      activeLabel: active,
      customLabel: request?.label,
      customError: customError,
      outcome: outcome,
    );
  }

  return result;
}
