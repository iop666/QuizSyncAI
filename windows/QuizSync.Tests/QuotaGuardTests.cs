using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 每日配额（`ai-contract.md` 第 4 节）：默认 200 次真实调用、不含缓存命中；
/// `dailyLimit ≤ 0` = 不设上限（仍记录用量）。
/// </summary>
public sealed class QuotaGuardTests
{
    private static QuizDatabase NewDatabase() => QuizDatabase.CreateFromProtocolSchema(":memory:");

    private static long TodayNoon()
    {
        var today = DateTimeOffset.Now.Date;
        return new DateTimeOffset(today.AddHours(12), TimeZoneInfo.Local.GetUtcOffset(today)).ToUnixTimeMilliseconds();
    }

    [Fact]
    public void Usage_is_counted_per_local_day_and_blocks_at_the_limit()
    {
        using var database = NewDatabase();
        var now = TodayNoon();
        var guard = new QuotaGuard(database, dailyLimit: 3, now: () => now);

        Assert.True(guard.CanCall);
        Assert.Equal(0, guard.UsedToday());

        guard.RecordUsage("m", "v1-abc", "hash-1", ok: true, latencyMs: 120);
        guard.RecordUsage("m", "v1-abc", "hash-2", ok: false, errorCode: "timeout");
        Assert.Equal(2, guard.UsedToday());
        Assert.True(guard.CanCall);

        guard.RecordUsage("m", "v1-abc", "hash-3", ok: true);
        Assert.Equal(3, guard.UsedToday());
        Assert.False(guard.CanCall, "达到上限就该拦住（明确提示，不静默失败）");
    }

    [Fact]
    public void Yesterdays_usage_does_not_count_toward_today()
    {
        using var database = NewDatabase();
        var now = TodayNoon();
        var guard = new QuotaGuard(database, dailyLimit: 2, now: () => now);
        guard.RecordUsage("m", "v1-abc", "hash-old", ok: true);

        // 把「今天」推到明天：昨天的用量不再计入。
        var tomorrow = now + (long)TimeSpan.FromDays(1).TotalMilliseconds;
        var tomorrowGuard = new QuotaGuard(database, dailyLimit: 2, now: () => tomorrow);
        Assert.Equal(0, tomorrowGuard.UsedToday());
        Assert.True(tomorrowGuard.CanCall);
    }

    [Fact]
    public void Zero_or_negative_limit_means_unlimited_but_still_records()
    {
        using var database = NewDatabase();
        var guard = new QuotaGuard(database, dailyLimit: 0, now: TodayNoon);
        Assert.True(guard.Unlimited);

        for (var i = 0; i < 250; i++)
        {
            Assert.True(guard.CanCall);
            guard.RecordUsage("m", "v1-abc", $"hash-{i}", ok: true);
        }

        Assert.Equal(250, guard.UsedToday());
        Assert.True(guard.CanCall, "不设上限时永不拦住调用");
    }

    [Fact]
    public void Usage_rows_keep_the_diagnostics_columns()
    {
        using var database = NewDatabase();
        var guard = new QuotaGuard(database, dailyLimit: 10, now: TodayNoon);
        guard.RecordUsage("qwen-vl-max", "v1-c63f8999", "abc123", ok: false, errorCode: "rate_limited", latencyMs: 4321);

        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT model, prompt_version, image_hash, ok, error_code, latency_ms FROM ai_usage";
        using var reader = command.ExecuteReader();
        Assert.True(reader.Read());
        Assert.Equal("qwen-vl-max", reader.GetString(0));
        Assert.Equal("v1-c63f8999", reader.GetString(1));
        Assert.Equal("abc123", reader.GetString(2));
        Assert.Equal(0, reader.GetInt32(3));
        Assert.Equal("rate_limited", reader.GetString(4));
        Assert.Equal(4321L, reader.GetInt64(5));
    }
}
