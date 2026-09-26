namespace QuizSync.Core;

/// <summary>
/// 重试策略（`ai-contract.md` 第 4 节）：
/// - 可重试：超时、连接失败、5xx、429；指数退避 **1s / 3s**；默认最多 2 次重试；
/// - 不可重试：400 / 401 / 403，直接失败；
/// - **JSON 解析失败的额外重试不占本预算**（那在引擎层单独处理）。
/// </summary>
public sealed class RetryPolicy
{
    /// <summary>各次重试前的等待时长。</summary>
    public static readonly TimeSpan[] BackoffSchedule = [TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(3)];

    private readonly Func<TimeSpan, Task> _sleeper;

    public RetryPolicy(int maxRetries = 2, Func<TimeSpan, Task>? sleeper = null)
    {
        MaxRetries = maxRetries;
        _sleeper = sleeper ?? (delay => Task.Delay(delay));
    }

    public int MaxRetries { get; }

    public int MaxAttempts => 1 + MaxRetries;

    /// <summary>第 `attempt` 次失败（0 起）后应等待的时长；无需再等待返回 null。</summary>
    public TimeSpan? BackoffBefore(int attempt)
    {
        if (attempt >= MaxRetries)
        {
            return null;
        }

        return BackoffSchedule[Math.Clamp(attempt, 0, BackoffSchedule.Length - 1)];
    }

    public bool ShouldRetry(AiException error, int attemptsSoFar) =>
        error.Retryable && attemptsSoFar < MaxRetries;

    internal Task SleepAsync(TimeSpan delay) => _sleeper(delay);

    /// <summary>
    /// 逐次执行 `action` 直到成功或重试预算耗尽。
    /// 返回成功值；最终失败抛出**最后一次**的 <see cref="AiException"/>。
    /// </summary>
    public async Task<T> ExecuteAsync<T>(
        Func<Task<T>> action,
        Action<int, AiException, TimeSpan?>? onError = null,
        CancellationToken cancellationToken = default)
    {
        var attempt = 0;
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                return await action().ConfigureAwait(false);
            }
            catch (AiException error)
            {
                var wait = BackoffBefore(attempt);
                var retryable = ShouldRetry(error, attempt);
                onError?.Invoke(attempt, error, retryable ? wait : null);
                if (!retryable)
                {
                    throw;
                }

                if (wait is not null)
                {
                    await SleepAsync(wait.Value).ConfigureAwait(false);
                }

                attempt++;
            }
        }
    }
}
