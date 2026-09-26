/// Lamport 时钟（`data-model.md` 2.1）。
///
/// 本地写入：`clock + 1`；收到对端 op：`max(clock, 收到的 lamport) + 1`。
/// 绝不用设备墙钟排序，墙钟只用于展示。
class LamportClock {
  int _value;

  LamportClock([this._value = 0]);

  int get value => _value;

  /// 本地写入前调用，返回新的 lamport。
  int tick() => ++_value;

  /// 收到对端 op 后调用，把本地时钟推高。
  void observe(int remoteLamport) {
    if (remoteLamport > _value) {
      _value = remoteLamport;
    }
    _value = _value + 1;
  }

  /// 恢复持久化的时钟值（启动时从库中最大 lamport 恢复）。
  void restore(int value) {
    if (value > _value) _value = value;
  }
}
