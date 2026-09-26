/// 手机（安卓）发起的一次识别任务的状态信号（M44 第 5 条）。
///
/// 为什么单独放一个文件：它要被三处共用 —— 服务端回调（`main.dart`）、全局
/// `ValueNotifier`（`state/app_scope.dart`）、悬浮窗外壳（`float_window_presenter.dart`）。
/// 放在任何一侧都会让另外两侧为了一个不可变小类互相 import。
library;

/// 任务状态 + 会话 id。
class RemoteTaskSignal {
  const RemoteTaskSignal(this.status, this.sessionId);

  /// `queued` / `analyzing` / `done` / `failed`（与 `task_executor` 一致）。
  final String status;

  /// 这次识别的会话 id；服务端早期状态可能还没有。
  final String? sessionId;

  /// 正在识别（手机提交后排队 / 分析中）—— 悬浮窗据此显示「手机正在识别…」。
  bool get busy => status == 'queued' || status == 'analyzing';

  /// 已经结束（成功或失败）—— 悬浮窗据此跳到新结果。
  bool get finished => status == 'done' || status == 'failed';

  @override
  bool operator ==(Object other) =>
      other is RemoteTaskSignal &&
      other.status == status &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(status, sessionId);

  @override
  String toString() => '$status:${sessionId ?? '-'}';
}
