/// 任务 / 会话状态机取值。`queued → analyzing → done/failed/cancelled`
/// （`data-model.md` sessions.status 与 tasks.status 共用同一组值）。
enum TaskState {
  queued('queued'),
  analyzing('analyzing'),
  done('done'),
  failed('failed'),
  cancelled('cancelled');

  final String wire;
  const TaskState(this.wire);

  static TaskState parse(String? raw) => TaskState.values.firstWhere(
        (s) => s.wire == raw,
        orElse: () => TaskState.queued,
      );

  bool get isTerminal =>
      this == TaskState.done || this == TaskState.failed || this == TaskState.cancelled;

  @override
  String toString() => wire;
}
