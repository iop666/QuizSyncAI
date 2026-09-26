using QuizSync.Core;
using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 分析缓存（key = 图片哈希 + prompt 版本 + 模型；TTL 30 天；只认 `status='done'` 且题目非空的会话）。
/// 与 Dart 侧 `AnalysisCache` 同一套判据。
/// </summary>
public sealed class AnalysisCacheTests
{
    private const string Now = "1700000000000";

    private static QuizDatabase NewDatabase() => QuizDatabase.CreateFromProtocolSchema(":memory:");

    private static void InsertSession(
        QuizDatabase database, string sessionId, long createdAt,
        string hash = "hash-1", string prompt = "v1-abc", string model = "m", string status = "done",
        long? deletedAt = null)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = """
            INSERT INTO sessions (session_id, image_hash, source_device, status, ai_model, prompt_version,
                                  created_at, updated_at, updated_by, deleted_at)
            VALUES ($sid, $hash, 'dev-1', $status, $model, $prompt, $at, $at, 'dev-1', $deleted)
            """;
        command.Parameters.AddWithValue("$sid", sessionId);
        command.Parameters.AddWithValue("$hash", hash);
        command.Parameters.AddWithValue("$status", status);
        command.Parameters.AddWithValue("$model", model);
        command.Parameters.AddWithValue("$prompt", prompt);
        command.Parameters.AddWithValue("$at", createdAt);
        command.Parameters.AddWithValue("$deleted", (object?)deletedAt ?? DBNull.Value);
        command.ExecuteNonQuery();
    }

    private static void InsertQuestion(QuizDatabase database, string questionId, string sessionId, int ordinal, string stem)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = """
            INSERT INTO questions (question_id, session_id, ordinal, stem, type, answer_text, analysis,
                                   confidence, options_json, choice_json, warnings_json, created_at, updated_at, updated_by)
            VALUES ($qid, $sid, $ord, $stem, 'single', 'B', '解析', 0.9, '[{"label":"A","text":"甲"},{"label":"B","text":"乙"}]',
                    '["B"]', '[]', 1700000000000, 1700000000000, 'dev-1')
            """;
        command.Parameters.AddWithValue("$qid", questionId);
        command.Parameters.AddWithValue("$sid", sessionId);
        command.Parameters.AddWithValue("$ord", ordinal);
        command.Parameters.AddWithValue("$stem", stem);
        command.ExecuteNonQuery();
    }

    private static AnalysisCache Cache(QuizDatabase database) =>
        new(database, now: () => long.Parse(Now, System.Globalization.CultureInfo.InvariantCulture));

    [Fact]
    public void Hit_returns_the_stored_questions()
    {
        using var database = NewDatabase();
        InsertSession(database, "s-1", 1699999999000);
        InsertQuestion(database, "q-1", "s-1", 0, "题目一");
        InsertQuestion(database, "q-2", "s-1", 1, "题目二");

        var hit = Cache(database).Lookup("hash-1", "v1-abc", "m");

        Assert.NotNull(hit);
        Assert.Equal("s-1", hit!.SessionId);
        Assert.Equal(2, hit.Questions.Count);
        Assert.Equal("题目一", hit.Questions[0].Stem);
        Assert.Equal(["B"], hit.Questions[0].Choice);
        Assert.Equal(QuestionType.SingleChoice, hit.Questions[0].Type);
        Assert.Equal(0.9, hit.Questions[0].Confidence, 3);
    }

    [Theory]
    [InlineData("hash-2", "v1-abc", "m")]   // 换了图
    [InlineData("hash-1", "v1-other", "m")] // 换了 prompt 版本
    [InlineData("hash-1", "v1-abc", "m2")]  // 换了模型
    public void Different_key_is_a_miss(string hash, string prompt, string model)
    {
        using var database = NewDatabase();
        InsertSession(database, "s-1", 1699999999000);
        InsertQuestion(database, "q-1", "s-1", 0, "题");

        Assert.Null(Cache(database).Lookup(hash, prompt, model));
    }

    [Fact]
    public void Not_done_or_deleted_sessions_are_not_cache_entries()
    {
        using var database = NewDatabase();
        InsertSession(database, "s-failed", 1699999999000, status: "failed");
        InsertQuestion(database, "q-1", "s-failed", 0, "题");
        Assert.Null(Cache(database).Lookup("hash-1", "v1-abc", "m"));

        using var database2 = NewDatabase();
        InsertSession(database2, "s-deleted", 1699999999000, deletedAt: 1699999999500);
        InsertQuestion(database2, "q-1", "s-deleted", 0, "题");
        Assert.Null(Cache(database2).Lookup("hash-1", "v1-abc", "m"));
    }

    [Fact]
    public void Entries_older_than_the_ttl_are_ignored()
    {
        using var database = NewDatabase();
        var tooOld = 1700000000000L - (long)TimeSpan.FromDays(31).TotalMilliseconds;
        InsertSession(database, "s-old", tooOld);
        InsertQuestion(database, "q-1", "s-old", 0, "题");

        Assert.Null(Cache(database).Lookup("hash-1", "v1-abc", "m"));
    }

    [Fact]
    public void Session_without_questions_falls_through_to_the_next_candidate()
    {
        using var database = NewDatabase();
        InsertSession(database, "s-empty", 1699999999000);          // 更新的那条没有题目
        InsertSession(database, "s-good", 1699999900000);           // 更旧但有题目
        InsertQuestion(database, "q-1", "s-good", 0, "题");

        var hit = Cache(database).Lookup("hash-1", "v1-abc", "m");

        Assert.Equal("s-good", hit!.SessionId);
    }

    [Fact]
    public void Newest_matching_session_wins()
    {
        using var database = NewDatabase();
        InsertSession(database, "s-old", 1699999900000);
        InsertQuestion(database, "q-old", "s-old", 0, "旧题");
        InsertSession(database, "s-new", 1699999999000);
        InsertQuestion(database, "q-new", "s-new", 0, "新题");

        var hit = Cache(database).Lookup("hash-1", "v1-abc", "m");

        Assert.Equal("s-new", hit!.SessionId);
        Assert.Equal("新题", hit.Questions[0].Stem);
    }

    [Fact]
    public void Empty_model_never_hits()
    {
        using var database = NewDatabase();
        InsertSession(database, "s-1", 1699999999000, model: string.Empty);
        InsertQuestion(database, "q-1", "s-1", 0, "题");

        Assert.Null(Cache(database).Lookup("hash-1", "v1-abc", string.Empty));
    }
}
