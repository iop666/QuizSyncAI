namespace QuizSync.Data;

/// <summary>
/// 每日配额（`ai-contract.md` 第 4 节）：默认 **200 次真实调用**（**不含缓存命中**）；
/// 达到上限要明确提示，不静默失败；每次真实调用记进 `ai_usage`。
///
/// `dailyLimit &lt;= 0` 表示**不设上限**（用户选项）：仍然照常记录用量（统计用），
/// 但永不拦住调用。
/// </summary>
public sealed class QuotaGuard(QuizDatabase database, int dailyLimit = 200, Func<long>? now = null)
{
    private readonly QuizDatabase _database = database;
    private readonly Func<long> _now = now ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

    public int DailyLimit { get; } = dailyLimit;

    /// <summary>是否「不设上限」（设置里选的那一项）。</summary>
    public bool Unlimited => DailyLimit <= 0;

    /// <summary>今日已用量（按**本机自然日**）。</summary>
    public int UsedToday()
    {
        var startOfToday = DateTimeOffset.FromUnixTimeMilliseconds(_now()).ToLocalTime().Date;
        var startMs = new DateTimeOffset(startOfToday, TimeZoneInfo.Local.GetUtcOffset(startOfToday))
            .ToUnixTimeMilliseconds();
        using var command = _database.Connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM ai_usage WHERE called_at >= $start";
        command.Parameters.AddWithValue("$start", startMs);
        return Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
    }

    public bool CanCall => Unlimited || UsedToday() < DailyLimit;

    /// <summary>记录一次真实调用（成功与否都记）。</summary>
    public void RecordUsage(
        string model,
        string promptVersion,
        string imageHash,
        bool ok,
        string? errorCode = null,
        long? latencyMs = null)
    {
        using var command = _database.Connection.CreateCommand();
        command.CommandText = """
            INSERT INTO ai_usage (id, called_at, model, prompt_version, image_hash, ok, error_code, latency_ms)
            VALUES ($id, $at, $model, $promptVersion, $imageHash, $ok, $errorCode, $latency)
            """;
        command.Parameters.AddWithValue("$id", Guid.NewGuid().ToString());
        command.Parameters.AddWithValue("$at", _now());
        command.Parameters.AddWithValue("$model", model);
        command.Parameters.AddWithValue("$promptVersion", promptVersion);
        command.Parameters.AddWithValue("$imageHash", imageHash);
        command.Parameters.AddWithValue("$ok", ok ? 1 : 0);
        command.Parameters.AddWithValue("$errorCode", (object?)errorCode ?? DBNull.Value);
        command.Parameters.AddWithValue("$latency", (object?)latencyMs ?? DBNull.Value);
        command.ExecuteNonQuery();
    }
}
