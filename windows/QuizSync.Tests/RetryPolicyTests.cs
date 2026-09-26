using System.Text.Json.Nodes;
using QuizSync.Core;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 重试策略（`ai-contract.md` 第 4 节）。与 Dart 侧 `test/ai/retry_test.dart` 同一套语义：
/// 只有超时/连接失败/5xx/429 重试，退避 1s → 3s，默认 2 次，其余立刻失败。
/// </summary>
public sealed class RetryPolicyTests
{
    private sealed class RecordingPolicy
    {
        public List<TimeSpan> Delays { get; } = [];

        public RetryPolicy Policy => new(maxRetries: 2, sleeper: delay =>
        {
            Delays.Add(delay);
            return Task.CompletedTask;
        });
    }

    private static Func<Task<string>> FailsWith(AiException error) =>
        () => Task.FromException<string>(error);

    [Theory]
    [InlineData(AiErrorKind.Timeout)]
    [InlineData(AiErrorKind.Network)]
    [InlineData(AiErrorKind.ServerError)]
    [InlineData(AiErrorKind.RateLimited)]
    public async Task Retryable_kinds_are_retried_until_the_budget_is_gone(AiErrorKind kind)
    {
        var recording = new RecordingPolicy();
        var attempts = 0;
        var error = new AiException(kind, "boom");

        var thrown = await Assert.ThrowsAsync<AiException>(() => recording.Policy.ExecuteAsync<string>(() =>
        {
            attempts++;
            return Task.FromException<string>(error);
        }));

        Assert.Same(error, thrown);
        Assert.Equal(3, attempts); // 1 次 + 2 次重试
        Assert.Equal([TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(3)], recording.Delays);
    }

    [Theory]
    [InlineData(AiErrorKind.BadRequest)]
    [InlineData(AiErrorKind.Auth)]
    [InlineData(AiErrorKind.Unknown)]
    public async Task Non_retryable_kinds_fail_immediately(AiErrorKind kind)
    {
        var recording = new RecordingPolicy();
        var attempts = 0;

        await Assert.ThrowsAsync<AiException>(() => recording.Policy.ExecuteAsync<string>(() =>
        {
            attempts++;
            return Task.FromException<string>(new AiException(kind, "nope"));
        }));

        Assert.Equal(1, attempts);
        Assert.Empty(recording.Delays);
    }

    [Fact]
    public async Task Success_after_a_retry_returns_the_value()
    {
        var recording = new RecordingPolicy();
        var attempts = 0;
        var value = await recording.Policy.ExecuteAsync(() =>
        {
            attempts++;
            return attempts < 2
                ? Task.FromException<string>(new AiException(AiErrorKind.Network, "flaky"))
                : Task.FromResult("ok");
        });

        Assert.Equal("ok", value);
        Assert.Equal(2, attempts);
        Assert.Equal([TimeSpan.FromSeconds(1)], recording.Delays);
    }

    [Fact]
    public void Backoff_schedule_and_attempt_budget_match_the_contract()
    {
        var policy = new RetryPolicy(sleeper: _ => Task.CompletedTask);
        Assert.Equal(3, policy.MaxAttempts); // 1 + 2
        Assert.Equal(TimeSpan.FromSeconds(1), policy.BackoffBefore(0));
        Assert.Equal(TimeSpan.FromSeconds(3), policy.BackoffBefore(1));
        Assert.Null(policy.BackoffBefore(2));

        Assert.True(policy.ShouldRetry(new AiException(AiErrorKind.Timeout, "t"), 0));
        Assert.True(policy.ShouldRetry(new AiException(AiErrorKind.Timeout, "t"), 1));
        Assert.False(policy.ShouldRetry(new AiException(AiErrorKind.Timeout, "t"), 2));
        Assert.False(policy.ShouldRetry(new AiException(AiErrorKind.Auth, "t"), 0));
    }

    [Fact]
    public async Task OnError_reports_the_wait_only_when_it_will_retry()
    {
        var recording = new RecordingPolicy();
        var reports = new List<(int Attempt, TimeSpan? Wait)>();
        var attempts = 0;

        await Assert.ThrowsAsync<AiException>(() => recording.Policy.ExecuteAsync<string>(
            () =>
            {
                attempts++;
                return Task.FromException<string>(new AiException(AiErrorKind.ServerError, "500"));
            },
            onError: (attempt, _, wait) => reports.Add((attempt, wait))));

        Assert.Equal(3, reports.Count);
        Assert.Equal(TimeSpan.FromSeconds(1), reports[0].Wait);
        Assert.Equal(TimeSpan.FromSeconds(3), reports[1].Wait);
        Assert.Null(reports[2].Wait); // 预算用完：不再等待
        Assert.Equal(3, attempts);
    }

    [Theory]
    [InlineData(400, AiErrorKind.BadRequest)]
    [InlineData(401, AiErrorKind.Auth)]
    [InlineData(403, AiErrorKind.Auth)]
    [InlineData(429, AiErrorKind.RateLimited)]
    [InlineData(500, AiErrorKind.ServerError)]
    [InlineData(503, AiErrorKind.ServerError)]
    [InlineData(418, AiErrorKind.Unknown)]
    public void Http_status_maps_to_the_contract_kinds(int status, AiErrorKind expected)
    {
        Assert.Equal(expected, AiException.FromStatus(status, "m").Kind);
    }

    [Fact]
    public void Secure_config_json_never_contains_the_api_key()
    {
        var config = new AiConfig { ApiKey = "sk-secret", Model = "m", ProviderId = "openai-compatible" };
        var json = config.ToSecureJson();
        Assert.False(json.ContainsKey("api_key"));
        Assert.DoesNotContain("sk-secret", json.ToJsonString(), StringComparison.Ordinal);
        Assert.Equal("m", json["model"]!.GetValue<string>());
    }
}
