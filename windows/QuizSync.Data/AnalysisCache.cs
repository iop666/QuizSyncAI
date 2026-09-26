using System.Text.Json;
using System.Text.Json.Nodes;
using QuizSync.Core;

namespace QuizSync.Data;

/// <summary>缓存命中的条目。</summary>
public sealed record CachedAnalysis(string SessionId, IReadOnlyList<Question> Questions, long CreatedAt);

/// <summary>
/// 分析缓存（`ai-contract.md` 第 4 节）：
/// key = `image_hash` + `prompt_version` + `model`；命中且距今 < 30 天 → 直接回放。
///
/// 存储**复用 `sessions` 表**（同 hash + 同 prompt 版本 + 同模型、`status='done'`、
/// 未删除、题目非空的最近一条会话就是缓存条目）—— 不新增表、不改 schema。
/// </summary>
public sealed class AnalysisCache(QuizDatabase database, TimeSpan? ttl = null, Func<long>? now = null)
{
    public static readonly TimeSpan DefaultTtl = TimeSpan.FromDays(30);

    private readonly QuizDatabase _database = database;
    private readonly TimeSpan _ttl = ttl ?? DefaultTtl;
    private readonly Func<long> _now = now ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

    public CachedAnalysis? Lookup(string imageHash, string promptVersion, string model)
    {
        if (string.IsNullOrEmpty(model) || string.IsNullOrEmpty(imageHash))
        {
            return null;
        }

        var threshold = _now() - (long)_ttl.TotalMilliseconds;

        // 按时间倒序看候选：最早的那条若题目为空就继续往前找（与 Dart 侧同一个循环语义）。
        var candidates = new List<(string SessionId, long CreatedAt)>();
        using (var command = _database.Connection.CreateCommand())
        {
            command.CommandText = """
                SELECT session_id, created_at FROM sessions
                WHERE image_hash = $hash AND status = 'done' AND prompt_version = $prompt
                  AND ai_model = $model AND deleted_at IS NULL AND created_at >= $threshold
                ORDER BY created_at DESC
                """;
            command.Parameters.AddWithValue("$hash", imageHash);
            command.Parameters.AddWithValue("$prompt", promptVersion);
            command.Parameters.AddWithValue("$model", model);
            command.Parameters.AddWithValue("$threshold", threshold);
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                candidates.Add((reader.GetString(0), reader.GetInt64(1)));
            }
        }

        foreach (var (sessionId, createdAt) in candidates)
        {
            var questions = QuestionsOfSession(sessionId);
            if (questions.Count > 0)
            {
                return new CachedAnalysis(sessionId, questions, createdAt);
            }
        }

        return null;
    }

    /// <summary>读某个会话的题目（按 ordinal 升序）。</summary>
    public IReadOnlyList<Question> QuestionsOfSession(string sessionId)
    {
        var questions = new List<Question>();
        using var command = _database.Connection.CreateCommand();
        command.CommandText = "SELECT * FROM questions WHERE session_id = $sid AND deleted_at IS NULL ORDER BY ordinal ASC";
        command.Parameters.AddWithValue("$sid", sessionId);
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            questions.Add(ReadQuestion(reader, sessionId));
        }

        return questions;
    }

    private static Question ReadQuestion(Microsoft.Data.Sqlite.SqliteDataReader reader, string sessionId)
    {
        string? Text(string column)
        {
            var index = reader.GetOrdinal(column);
            return reader.IsDBNull(index) ? null : reader.GetString(index);
        }

        long Number(string column)
        {
            var index = reader.GetOrdinal(column);
            return reader.IsDBNull(index) ? 0L : reader.GetInt64(index);
        }

        double Real(string column)
        {
            var index = reader.GetOrdinal(column);
            return reader.IsDBNull(index) ? 0d : reader.GetDouble(index);
        }

        bool Flag(string column) => Number(column) != 0;

        return new Question
        {
            QuestionId = Text("question_id") ?? string.Empty,
            SessionId = sessionId,
            Ordinal = (int)Number("ordinal"),
            QuestionNo = Text("question_no"),
            Stem = Text("stem") ?? string.Empty,
            Material = Text("material") ?? string.Empty,
            Type = QuestionTypes.Parse(Text("type")),
            Options = ReadOptions(Text("options_json")),
            Choice = ReadStringArray(Text("choice_json")),
            AnswerText = Text("answer_text"),
            Analysis = Text("analysis") ?? string.Empty,
            Confidence = Real("confidence"),
            NeedReview = Flag("need_review"),
            AnswerInImage = Flag("answer_in_image"),
            Incomplete = Flag("incomplete"),
            AnswerGuessed = Flag("answer_guessed"),
            Warnings = ReadStringArray(Text("warnings_json")),
            CreatedAt = Number("created_at"),
            UpdatedAt = Number("updated_at"),
            UpdatedBy = Text("updated_by") ?? string.Empty,
        };
    }

    private static List<Option> ReadOptions(string? json)
    {
        var options = new List<Option>();
        if (ParseArray(json) is not { } array)
        {
            return options;
        }

        foreach (var item in array)
        {
            if (item is JsonObject option)
            {
                options.Add(Option.FromJson(option));
            }
        }

        return options;
    }

    private static List<string> ReadStringArray(string? json) =>
        ParseArray(json) is { } array ? [.. array.Select(item => item?.ToString() ?? string.Empty)] : [];

    private static JsonArray? ParseArray(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            return JsonNode.Parse(json) as JsonArray;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
