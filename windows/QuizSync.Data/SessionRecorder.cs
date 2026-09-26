using System.Globalization;
using System.Text.Json;

namespace QuizSync.Data;

/// <summary>要落库的一道题。刻意**不依赖 Core / Provider**（数据层不往上依赖），
/// 由调用方把 <c>Question</c> 映射进来。</summary>
public sealed record RecordedQuestion(
    int Ordinal,
    string Stem,
    string Type,
    string? QuestionNo = null,
    string? AnswerText = null,
    string Analysis = "",
    IReadOnlyList<string>? Choice = null,
    double Confidence = 0.5,
    bool NeedReview = false);

/// <summary>库里的一行会话（历史列表用）。</summary>
public sealed record RecordedSession(
    string SessionId,
    string ImageHash,
    string SourceDevice,
    string Status,
    int QuestionCount,
    long CreatedAt,
    string? AiProvider,
    string? AiModel,
    int LatencyMs,
    bool Cached);

/// <summary>
/// 把一次识别结果落成 `sessions` + `questions` 两个实体，**并生成同步 op**（Android 端可拉取）。
///
/// 列名与 NOT NULL 约束全部来自协议 schema（`schema/schema-v1.sql`）与一致性向量
/// （`conformance/vectors/sync.ndjson` 的 `op-s1-create` / `op-q1-create`）—— **不是手抄的**：
/// * `sessions` 必须给：image_hash / source_device / status / created_at / updated_at / updated_by
///   （其余如 question_count / cached 有默认值，但一起写更省一次改动）；
/// * `questions` 必须给：session_id / ordinal / stem / type / created_at / updated_at / updated_by；
///   `choice_json` 与 `need_review` 带 NOT NULL 默认值，但选择题的答案就在 choice_json 里，
///   不写就等于历史里看不到答案。
///
/// 走 `LocalStore.WriteLocal` 而不是直接 INSERT：**要生成 op**，否则这些记录永远同步不到手机。
/// </summary>
public static class SessionRecorder
{
    /// <summary>落一次识别；返回 session_id。</summary>
    public static string Record(
        LocalStore store,
        string imageHash,
        string sourceDevice,
        IReadOnlyList<RecordedQuestion> questions,
        long now,
        string? aiProvider = null,
        string? aiModel = null,
        int latencyMs = 0,
        bool cached = false)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(questions);

        var sessionId = $"s-{Guid.NewGuid():N}";
        store.WriteLocal(SyncEntities.Session, sessionId, new Dictionary<string, object?>
        {
            ["image_hash"] = imageHash,
            ["source_device"] = sourceDevice,
            ["status"] = "done",
            ["question_count"] = (long)questions.Count,
            ["ai_provider"] = aiProvider,
            ["ai_model"] = aiModel,
            ["latency_ms"] = (long)latencyMs,
            ["cached"] = cached ? 1L : 0L,
            ["created_at"] = now,
            ["updated_at"] = now,
            ["updated_by"] = sourceDevice,
        });

        for (var index = 0; index < questions.Count; index++)
        {
            var question = questions[index];
            store.WriteLocal(SyncEntities.Question, $"q-{Guid.NewGuid():N}", new Dictionary<string, object?>
            {
                ["session_id"] = sessionId,
                ["ordinal"] = (long)(question.Ordinal == 0 ? index : question.Ordinal),
                ["question_no"] = question.QuestionNo,
                ["stem"] = question.Stem,
                ["type"] = question.Type,
                ["answer_text"] = question.AnswerText,
                ["analysis"] = question.Analysis,
                ["choice_json"] = JsonSerializer.Serialize(question.Choice ?? []),
                ["confidence"] = question.Confidence,
                ["need_review"] = question.NeedReview ? 1L : 0L,
                ["created_at"] = now,
                ["updated_at"] = now,
                ["updated_by"] = sourceDevice,
            });
        }

        return sessionId;
    }

    /// <summary>最近的会话（新的在前）。软删除的不算。</summary>
    public static IReadOnlyList<RecordedSession> RecentSessions(QuizDatabase database, int limit = 50)
    {
        ArgumentNullException.ThrowIfNull(database);
        using var command = database.Connection.CreateCommand();
        command.CommandText =
            """
            SELECT session_id, image_hash, source_device, status, question_count,
                   created_at, ai_provider, ai_model, latency_ms, cached
              FROM sessions
             WHERE deleted_at IS NULL
             ORDER BY created_at DESC, rowid DESC
             LIMIT $limit
            """;
        command.Parameters.AddWithValue("$limit", limit);

        var sessions = new List<RecordedSession>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            sessions.Add(new RecordedSession(
                SessionId: reader.GetString(0),
                ImageHash: reader.GetString(1),
                SourceDevice: reader.GetString(2),
                Status: reader.GetString(3),
                QuestionCount: reader.GetInt32(4),
                CreatedAt: reader.GetInt64(5),
                AiProvider: reader.IsDBNull(6) ? null : reader.GetString(6),
                AiModel: reader.IsDBNull(7) ? null : reader.GetString(7),
                LatencyMs: reader.IsDBNull(8) ? 0 : reader.GetInt32(8),
                Cached: !reader.IsDBNull(9) && reader.GetInt64(9) != 0));
        }

        return sessions;
    }

    /// <summary>某个会话下的题目（按 ordinal）。</summary>
    public static IReadOnlyList<RecordedQuestion> QuestionsOf(QuizDatabase database, string sessionId)
    {
        ArgumentNullException.ThrowIfNull(database);
        using var command = database.Connection.CreateCommand();
        command.CommandText =
            """
            SELECT ordinal, stem, type, question_no, answer_text, analysis, choice_json, confidence, need_review
              FROM questions
             WHERE session_id = $session AND deleted_at IS NULL
             ORDER BY ordinal
            """;
        command.Parameters.AddWithValue("$session", sessionId);

        var questions = new List<RecordedQuestion>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            questions.Add(new RecordedQuestion(
                Ordinal: reader.GetInt32(0),
                Stem: reader.GetString(1),
                Type: reader.GetString(2),
                QuestionNo: reader.IsDBNull(3) ? null : reader.GetString(3),
                AnswerText: reader.IsDBNull(4) ? null : reader.GetString(4),
                Analysis: reader.IsDBNull(5) ? string.Empty : reader.GetString(5),
                Choice: ParseChoice(reader.IsDBNull(6) ? null : reader.GetString(6)),
                Confidence: reader.IsDBNull(7) ? 0.5 : reader.GetDouble(7),
                NeedReview: !reader.IsDBNull(8) && reader.GetInt64(8) != 0));
        }

        return questions;
    }

    private static List<string> ParseChoice(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? [];
        }
        catch (JsonException)
        {
            // 脏数据不该让整个历史页打不开。
            return [];
        }
    }
}
