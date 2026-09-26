import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:quizsync_core/quizsync_core.dart' show AppLogger;

import 'hotkeys.dart';

/// 诊断追踪：统一进应用日志（导出日志时可见）。
void hotkeyTrace(String line) => AppLogger.instance.info('hotkey', line);

/// 一个槽位的注册意愿（线程重建后照它重新注册）。
class _HotkeyBinding {
  final String slot;
  final int vk;
  final int modifiers;
  final String label;
  final void Function() onTrigger;

  const _HotkeyBinding(
      this.slot, this.vk, this.modifiers, this.label, this.onTrigger);
}

/// Windows 全局热键（`RegisterHotKey` + `PeekMessageW` 轮询泵）。
///
/// ## 为什么是「一个长期存活的 isolate + 固定 id + 显式注销」
///
/// `RegisterHotKey(NULL, id, ...)` 把热键绑在**线程**的消息队列上，而 isolate
/// 退出 ≠ 线程退出（线程回 VM 线程池复用）：旧注册会跟着线程活下来，新 isolate
/// 落到同一线程时同 id 注册失败（表现为「改了热键不生效、回退到别的键」），
/// 而**旧键照常生效**、它的 `WM_HOTKEY` 会被该线程上另一个槽位的轮询泵读走
/// （表现为「按截图键执行了追加页」）。
///
/// 所以：所有热键共用一个 isolate、每个槽位固定 id、每次注册前先
/// `UnregisterHotKey` 同 id、退出前显式注销全部。
///
/// ## M46 第 1 条：线程号也要钉死（照搬 Server 的做法）
///
/// 「共用一个 isolate ⇒ 线程不再换手」**不成立**：这个 isolate 每 `await` 一次，
/// VM 就可能把它调度到另一条池线程上（Server 侧的诊断版实测 28 秒里换了
/// **327 次**手）。对注册绑在线程上的 Win32 调用这是致命的，两种失效都会出现：
///
/// * **注册被丢弃**：持有注册的那条池线程被 VM 收走 → 系统里的注册跟着消失，
///   进程还活着、界面还写着「F8」，按下去谁都不响应，**Win32 不给任何通知**；
/// * **消息被晾着**：注册还在，但泵跑在另一条线程上 → `WM_HOTKEY` 投递到旧线程
///   的队列，没人取，表现同样是「按键没反应」。
///
/// 对策（与 `server/lib/src/hotkey_service.dart` 同一套）：
/// 1. 后台线程的循环**一次 await 都不做**（同步 `PeekMessageW` + `Sleep`），线程号
///    因此钉死不变 —— 代价是收不到 `SendPort` 消息，于是命令改走一块**共享内存**
///    （主 isolate 写参数 + 自增 seq，后台线程轮询 seq，回写 replySeq 作应答）；
/// 2. 后台线程**每 2 秒自检一次**：拿同一个 id 再注册一次 —— 还持有必然失败
///    （1409 = ERROR_HOTKEY_ALREADY_REGISTERED），能成功就说明注册真的丢了，
///    当场补回来并写一行日志。
class HotkeyService implements HotkeyRegistrar {
  static const int _kRegister = 1;
  static const int _kUnregister = 2;
  static const int _kQuit = 3;
  static const int _kFired = 11;
  static const int _kTrace = 12;
  static const int _kReady = 13;

  // 命令槽的下标（一块原生 int64 × 8 的内存，主 isolate 与热键线程共用）：
  //   主 isolate：写参数 → **最后**写 seq（热键线程先读 seq，变了才看参数）
  //   热键线程：处理完写 replyValue → **最后**写 replySeq（主 isolate 轮询它）
  static const int _sSeq = 0;
  static const int _sOp = 1;
  static const int _sId = 2;
  static const int _sVk = 3;
  static const int _sMods = 4;
  static const int _sReplySeq = 5;
  static const int _sReplyValue = 6;

  /// 诊断输出（默认进应用日志）。
  final void Function(String message)? trace;

  ReceivePort? _events;
  ReceivePort? _control;
  Future<void>? _starting;

  /// 命令槽（见 [_sSeq]）：热键线程**不能 await**，所以命令不能走 SendPort。
  Pointer<Int64>? _slot;
  int _seq = 0;
  int _replySeq = 0;

  /// 热键线程报「已就绪」用。
  ///
  /// 必须有这道握手：`Isolate.spawn` 只保证 isolate 被创建，不保证它的入口已经
  /// 跑起来。主 isolate 抢在它之前写命令的话，那条命令永远等不到应答（实测就是
  /// 第一个热键注册超时失败）。等它报 ready 之后再发命令。
  Completer<void>? _ready;

  /// 热键 id → 触发回调（热键线程只回传 id）。
  final Map<int, void Function()> _handlers = {};

  /// 热键 id → 「用户希望它注册成什么样」。线程重建后照这份重新注册。
  final Map<int, _HotkeyBinding> _bindings = {};

  /// 热键 id → 当前生效键的标签（给设置页显示）。
  final Map<int, String> _labelOfId = {};

  var _disposed = false;
  var _restoring = false;

  /// 当前真正注册着的 id（注销/退出用）。
  final Set<int> _registered = {};

  /// 最近一次注册失败的 Win32 错误码（0 = 成功）。
  ///
  /// 1409 = `ERROR_HOTKEY_ALREADY_REGISTERED`（被别的程序占了，或本进程没释放干净）。
  int lastErrorCode = 0;

  /// 槽位名 → 热键 id。产品内的两个槽位用固定 id（互不相同）；其它按需分配。
  final Map<String, int> _slotIds = {
    'capture': 1,
    'multipage': 2,
  };
  int _nextSlotId = 3;

  /// 取（必要时分配）某个槽位的热键 id。
  int _idFor(String slot) => _slotIds.putIfAbsent(slot, () => _nextSlotId++);

  HotkeyService({this.trace});

  /// 某个 slot 当前生效的组合键标签；null = 没注册上。
  String? activeLabel(String slot) => _labelOfId[_idFor(slot)];

  /// 注册组合键。成功返回 true 并在每次按下时回调 [onTrigger]。
  /// [slot] 区分用途（'capture' / 'multipage'）。
  @override
  Future<bool> register({
    required String slot,
    required int vk,
    required int nativeModifiers,
    required String label,
    required void Function() onTrigger,
  }) async {
    final id = _idFor(slot);
    await unregister(slot: slot);
    if (!await _ensureThread()) return false;

    // 紧接着注销之后立刻注册，偶尔会拿到 1409 —— 那是**我们自己**上一个注册还没被
    // 系统彻底释放，不是别人占用。隔一小会儿重试几次；连续失败才判定成被占用。
    var error = 0;
    for (var attempt = 0; attempt < 6; attempt++) {
      error = await _command(_kRegister, id, vk, nativeModifiers);
      if (error == 0) {
        if (attempt > 0) {
          hotkeyTrace('register[$slot] 第 ${attempt + 1} 次尝试注册成功（前几次被系统判为已注册）');
        }
        break;
      }
      if (error != 1409) break; // 不是「已被注册」，重试没有意义
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    lastErrorCode = error;
    hotkeyTrace('register[$slot] id=$id vk=$vk mods=$nativeModifiers -> $label '
        '${error == 0 ? 'OK' : '失败 err=$error'}');
    if (error != 0) return false;
    _handlers[id] = onTrigger;
    _labelOfId[id] = label;
    _bindings[id] = _HotkeyBinding(slot, vk, nativeModifiers, label, onTrigger);
    _registered.add(id);
    return true;
  }

  /// 注销热键（[slot] 为 null 时注销全部）。
  ///
  /// **等后台线程真把 `UnregisterHotKey` 调完再返回**：否则紧接着的
  /// `RegisterHotKey` 会撞上自己还没释放的注册（1409，见 [register]）。
  @override
  Future<void> unregister({String? slot}) async {
    if (_slot == null) return;
    final ids = slot == null ? _registered.toList() : <int>[_idFor(slot)];
    if (slot == null) {
      _handlers.clear();
      _labelOfId.clear();
      _bindings.clear();
      _registered.clear();
    } else {
      final id = _idFor(slot);
      _handlers.remove(id);
      _labelOfId.remove(id);
      _bindings.remove(id);
      _registered.remove(id);
    }
    for (final id in ids) {
      await _command(_kUnregister, id, 0, 0);
    }
  }

  /// 彻底停掉后台线程（退出程序时用；线程退出前会显式注销全部热键）。
  ///
  /// 注意不是 [HotkeyRegistrar] 的成员（那个接口只有注册/注销，单测的假实现不需要
  /// 线程生命周期），只有真实的 [HotkeyService] 才有。
  Future<void> dispose() async {
    _disposed = true;
    _handlers.clear();
    _labelOfId.clear();
    _bindings.clear();
    _registered.clear();
    final slot = _slot;
    final events = _events;
    final control = _control;
    _events = null;
    _control = null;
    if (slot != null) {
      // 直接写退出标志（不用 _command：它要等回复，而线程退出时不会再回）。
      _seq++;
      slot[_sOp] = _kQuit;
      slot[_sSeq] = _seq;
      // 给后台线程一点时间跑完注销，然后收尾（不 await 太久，退出要利落）。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      calloc.free(slot);
      _slot = null;
    }
    _starting = null;
    events?.close();
    control?.close();
  }

  /// 命令槽还没建好就建（顺带把后台线程拉起来）。
  Future<bool> _ensureThread() async {
    if (_slot != null) return true;
    try {
      await (_starting ??= _start());
      return _slot != null;
    } catch (e) {
      hotkeyTrace('后台热键线程启动失败：$e');
      return false;
    }
  }

  /// 把一条命令交给后台线程并等它的结果（Win32 错误码；-1 = 超时/线程不在）。
  Future<int> _command(int op, int id, int vk, int mods) async {
    final slot = _slot;
    if (slot == null) return -1;
    _seq++;
    final mine = _seq;
    slot[_sId] = id;
    slot[_sVk] = vk;
    slot[_sMods] = mods;
    slot[_sOp] = op;
    slot[_sSeq] = mine; // 最后写 seq：后台线程读到它才认为参数齐了
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final reply = slot[_sReplySeq];
      if (reply >= mine) {
        _replySeq = reply;
        return slot[_sReplyValue];
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return -1;
  }

  Future<void> _start() async {
    final events = ReceivePort();
    // 后台线程一死，热键就**再也不响应**（系统里的注册还在，只是没人收 WM_HOTKEY），
    // 所以异常 / 退出两个事件都要接出来写日志并尝试重建。
    final control = ReceivePort();
    events.listen(_onMessage);
    control.listen((raw) {
      if (raw is List && raw.isNotEmpty) {
        hotkeyTrace('后台热键线程异常：${raw.map((e) => '$e').join(' | ')}');
        unawaited(_restoreAfterDeath('异常'));
      } else {
        hotkeyTrace(_disposed
            ? '后台热键线程已退出（正常退出）'
            : '后台热键线程已退出，正在重建…（exit=$raw）');
        if (!_disposed) unawaited(_restoreAfterDeath('退出'));
      }
    });
    final slot = _slot ??= calloc<Int64>(8);
    final ready = Completer<void>();
    _ready = ready;
    try {
      await Isolate.spawn(
        _hotkeyLoop,
        <dynamic>[events.sendPort, slot.address],
        onError: control.sendPort,
        onExit: control.sendPort,
        // 出错不杀线程：命令处理器里的一次异常不该让热键整体失效。
        errorsAreFatal: false,
      );
      await ready.future.timeout(const Duration(seconds: 3));
      _events = events;
      _control = control;
    } catch (e) {
      events.close();
      control.close();
      _events = null;
      _control = null;
      rethrow;
    }
  }

  /// 后台线程死了之后重建它，并按 [_bindings] 把热键全部重新注册回来。
  Future<void> _restoreAfterDeath(String reason) async {
    if (_disposed || _restoring) return;
    _restoring = true;
    try {
      // M47：这里原来只清 `_starting`、把 `_slot` 留着 —— 而 `_ensureThread()`
      // 见 `_slot != null` 就直接返回 true，于是**根本没有重新 spawn**：设置页还
      // 显示「已生效」、日志写着「正在重建」，按键却毫无反应（新线程不存在，命令
      // 写进共享内存没人读，每次注册等满 3 秒后以 err=-1 失败）。
      await _respawn(reason);
      final bindings = _bindings.values.toList();
      for (final b in bindings) {
        final ok = await register(
          slot: b.slot,
          vk: b.vk,
          nativeModifiers: b.modifiers,
          label: b.label,
          onTrigger: b.onTrigger,
        );
        hotkeyTrace('重建后重新注册 ${b.slot}：${ok ? '成功' : '失败（err=$lastErrorCode）'}');
      }
    } catch (e) {
      hotkeyTrace('重建后台热键线程失败：$e');
    } finally {
      _restoring = false;
    }
  }

  /// 真的把后台热键线程再拉起来（复用同一块共享内存与两个端口）。
  Future<void> _respawn(String reason) async {
    final slot = _slot;
    final events = _events;
    final control = _control;
    if (slot == null || events == null || control == null) {
      // 连槽位/端口都没有（说明启动那一步就没成功）：完整走一遍启动。
      _starting = null;
      await _ensureThread();
      return;
    }
    // 共享内存那块不扔（新线程接着用），只把回复水位对齐到当前命令号，
    // 免得新线程重复执行那条已经没人等的旧命令。
    _replySeq = slot[_sSeq];
    slot[_sReplySeq] = _replySeq;
    final ready = Completer<void>();
    _ready = ready;
    hotkeyTrace('正在重建后台热键线程（$reason）…');
    await Isolate.spawn(
      _hotkeyLoop,
      <dynamic>[events.sendPort, slot.address],
      onError: control.sendPort,
      onExit: control.sendPort,
      // 出错不杀线程：命令处理器里的一次异常不该让热键整体失效。
      errorsAreFatal: false,
    );
    await ready.future.timeout(const Duration(seconds: 3));
    hotkeyTrace('后台热键线程已重建，准备重新注册热键');
  }

  /// 探测本机 F1–F12 里哪些键**现在没人占用**（注册一次、立刻注销）。
  ///
  /// 只在注册失败时调用一次：用户第一次撞上「热键被别的程序占用」时，最需要的
  /// 就是一句「那我该换成哪个键」。用专用 id（90），不碰两个槽位的 1/2。
  Future<List<String>> probeFreeFunctionKeys() async {
    if (!await _ensureThread()) return const [];
    const probeId = 90;
    final free = <String>[];
    for (var i = 1; i <= 12; i++) {
      final vk = 0x70 + i - 1;
      final err = await _command(_kRegister, probeId, vk, 0);
      if (err != 0) continue;
      free.add('F$i');
      await _command(_kUnregister, probeId, 0, 0);
    }
    return free;
  }

  /// 后台线程发回来的消息：只有「就绪 / 触发了 / 诊断文字」三种
  /// （命令回复走共享内存）。
  void _onMessage(dynamic raw) {
    if (raw is! List || raw.isEmpty) return;
    switch (raw[0]) {
      case _kReady:
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
      case _kTrace:
        hotkeyTrace(raw[1].toString());
      case _kFired:
        final id = raw[1];
        if (id is int) _handlers[id]?.call();
    }
  }
}

/// 后台热键线程：注册 + `PeekMessageW` 轮询泵。
///
/// ## 这个函数**绝不能 await**（M46 的关键结论，与 Server 同一套）
///
/// 只要 `await` 一次，VM 就可能把本 isolate 换到另一条池线程，注册就跟着旧线程
/// 走了。所以这里是同步循环：`Sleep` + `PeekMessageW`，一次都不让出执行权。
/// 代价是收不到 `SendPort` 消息 —— 命令改走共享内存（见 [HotkeyService._sSeq]）。
/// 触发事件仍然用 `SendPort.send`（发送是同步的，不需要 await）。
void _hotkeyLoop(List<dynamic> args) {
  final toMain = args[0] as SendPort;
  final slot = Pointer<Int64>.fromAddress(args[1] as int);
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final registerHotKey = user32.lookupFunction<
      Int32 Function(IntPtr, Int32, Uint32, Uint32),
      int Function(int, int, int, int)>('RegisterHotKey');
  final unregisterHotKey = user32.lookupFunction<
      Int32 Function(IntPtr, Int32),
      int Function(int, int)>('UnregisterHotKey');
  final peekMessage = user32.lookupFunction<
      Int32 Function(Pointer<MSG>, IntPtr, Uint32, Uint32, Uint32),
      int Function(Pointer<MSG>, int, int, int, int)>('PeekMessageW');
  final getLastError = kernel32.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError');
  final setLastError =
      kernel32.lookupFunction<Void Function(Uint32), void Function(int)>(
          'SetLastError');
  final sleep =
      kernel32.lookupFunction<Void Function(Uint32), void Function(int)>('Sleep');

  const wmHotkey = 0x0312;
  const pmRemove = 0x0001;

  final registered = <int>{};
  /// id → [vk, mods]：定期自检要用「当初注册的是什么键」。
  final keys = <int, List<int>>{};
  var quit = false;
  var lastCheck = DateTime.now().millisecondsSinceEpoch;
  /// 已经处理到哪条命令（共享内存里的 seq）。启动时对齐到当前值：上一条命令是
  /// **别人**在等的，本线程不重复执行它。
  var seenSeq = slot[HotkeyService._sSeq];

  // 先把「就绪」报给主 isolate，再进循环（否则第一条命令永远等不到应答）。
  toMain.send(<dynamic>[HotkeyService._kReady]);

  final msg = calloc<MSG>();
  try {
    while (!quit) {
      try {
        // ---- 处理命令（共享内存轮询，不需要 await）----
        final seq = slot[HotkeyService._sSeq];
        if (seq != seenSeq) {
          final op = slot[HotkeyService._sOp];
          final id = slot[HotkeyService._sId];
          final vk = slot[HotkeyService._sVk];
          final mods = slot[HotkeyService._sMods];
          seenSeq = seq;
          var reply = 0;
          switch (op) {
            case HotkeyService._kRegister:
              // 先显式注销同 id 的旧注册：RegisterHotKey 不会替你替换
              // 「同线程 + 同 id + 不同键」的旧注册，直接注册会失败。
              // （`SetLastError(0)` 是 Win32 的硬要求：成功的调用不会清零上一次的
              //   错误码，不归零就会读到陈旧值，日志里会看到假的错误码。）
              setLastError(0);
              final unregOk = unregisterHotKey(0, id);
              final unregErr = unregOk != 0 ? 0 : getLastError();
              registered.remove(id);
              setLastError(0);
              final ok = registerHotKey(0, id, mods, vk) != 0;
              reply = ok ? 0 : getLastError();
              if (ok) {
                registered.add(id);
                keys[id] = <int>[vk, mods];
              } else {
                toMain.send(<dynamic>[
                  HotkeyService._kTrace,
                  'register id=$id vk=0x${vk.toRadixString(16)} mods=$mods 失败 '
                      '(unregister=$unregOk err=$unregErr, register err=$reply)',
                ]);
              }
            case HotkeyService._kUnregister:
              setLastError(0);
              final ok = unregisterHotKey(0, id);
              final err = ok != 0 ? 0 : getLastError();
              registered.remove(id);
              keys.remove(id);
              if (ok == 0 && err != 1419 /* ERROR_HOTKEY_NOT_REGISTERED 属正常 */) {
                toMain.send(<dynamic>[
                  HotkeyService._kTrace,
                  'unregister id=$id 失败 err=$err',
                ]);
              }
            case HotkeyService._kQuit:
              quit = true;
          }
          slot[HotkeyService._sReplyValue] = reply;
          slot[HotkeyService._sReplySeq] = seq; // 最后写：主 isolate 轮询它
        }

        // ---- 收热键消息 ----
        var has = peekMessage(msg, 0, 0, 0, pmRemove);
        while (has != 0) {
          if (msg.ref.message == wmHotkey) {
            final id = msg.ref.wParam;
            // 按了热键却「没反应」时，日志必须能回答「到底有没有收到这个键」。
            if (registered.contains(id)) {
              toMain.send(<dynamic>[HotkeyService._kFired, id]);
            } else {
              toMain.send(<dynamic>[
                HotkeyService._kTrace,
                'WM_HOTKEY id=$id 但本线程没有注册它（已忽略）',
              ]);
            }
          }
          has = peekMessage(msg, 0, 0, 0, pmRemove);
        }
      } catch (e) {
        // 单次异常不允许终止轮询泵：泵一停，系统里的注册还在、按键却没人收，
        // 表现就是「热键突然全部失灵」而且毫无报错。
        toMain.send(<dynamic>[HotkeyService._kTrace, '热键泵异常：$e']);
      }
      if (quit) break;

      // ---- 注册自检（每 2 秒一次，兜底）----
      //
      // 本函数不 await，正常情况下注册不会掉；但留一道兜底：拿同一个 id + 同一个键
      // 再注册一次 —— 还持有必然失败并给出 1409，已经丢了会成功（顺手补回来）。
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (keys.isNotEmpty && nowMs - lastCheck >= 2000) {
        lastCheck = nowMs;
        for (final id in keys.keys.toList()) {
          final key = keys[id]!;
          setLastError(0);
          final again = registerHotKey(0, id, key[1], key[0]);
          if (again != 0) {
            registered.add(id);
            toMain.send(<dynamic>[
              HotkeyService._kTrace,
              '自检发现 id=$id（vk=0x${key[0].toRadixString(16)}）的系统注册已丢失，已自动补回',
            ]);
          }
        }
      }

      // 同步睡一小会儿：**不能 await**（await 会让 VM 把本 isolate 换到别的线程）。
      sleep(15);
    }
  } catch (e, stack) {
    toMain.send(<dynamic>[
      HotkeyService._kTrace,
      '热键线程主循环异常终止：$e\n$stack',
    ]);
    rethrow;
  } finally {
    // 退出前**显式**注销：线程会回到 VM 线程池被复用，不注销的话旧注册会跟着
    // 线程活下来，下一次启动就串键（见类注释）。
    for (final id in registered) {
      unregisterHotKey(0, id);
    }
    registered.clear();
    calloc.free(msg);
    toMain.send(<dynamic>[HotkeyService._kTrace, '热键线程结束（quit=$quit）']);
  }
}

/// Win32 MSG（x64，48 字节）。Dart FFI Struct 默认 packed，必须手工补
/// 对齐字段，否则 PeekMessageW 写越界且 wParam 错位。
final class MSG extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int message;
  @Uint32()
  external int pad1; // 4 字节对齐，使 wParam 落在 8 倍数偏移
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  @Uint32()
  external int pad2;
  @IntPtr()
  external int pt; // POINT（两个 LONG）合为一个 8 字节成员
}
