import 'provider.dart';

/// 重试策略（`ai-contract.md` 第 4 节）：
/// - 可重试：超时、连接失败、5xx、429；指数退避 1s / 3s；默认最多 2 次重试。
/// - 不可重试：400 / 401 / 403，直接失败。
/// - JSON 解析失败的额外重试在 AnalysisEngine 里单独处理，不占本预算。
class RetryPolicy {
  /// 各次重试前的等待时长。
  static const backoffSchedule = [Duration(seconds: 1), Duration(seconds: 3)];

  final int maxRetries;
  final Future<void> Function(Duration d) sleeper;

  const RetryPolicy({this.maxRetries = 2, this.sleeper = defaultSleep});

  static Future<void> defaultSleep(Duration d) => Future<void>.delayed(d);

  int get maxAttempts => 1 + maxRetries;

  /// 第 attempt 次失败（0 起）后应等待的时长；无需再等待返回 null。
  Duration? backoffBefore(int attempt) {
    if (attempt >= maxRetries) return null;
    return backoffSchedule[attempt.clamp(0, backoffSchedule.length - 1)];
  }

  bool shouldRetry(AiException e, int attemptsSoFar) =>
      e.retryable && attemptsSoFar < maxRetries;
}

/// 逐次执行 [action] 直到成功或重试预算耗尽。
/// 返回成功值；最终失败抛出最后一次的 [AiException]。
Future<T> withRetry<T>(
  RetryPolicy policy,
  Future<T> Function() action, {
  void Function(int attempt, AiException error, Duration? willWait)? onError,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await action();
    } on AiException catch (e) {
      final wait = policy.backoffBefore(attempt);
      final retryable = policy.shouldRetry(e, attempt);
      onError?.call(attempt, e, retryable ? wait : null);
      if (!retryable) rethrow;
      if (wait != null) await policy.sleeper(wait);
      attempt++;
    }
  }
}
