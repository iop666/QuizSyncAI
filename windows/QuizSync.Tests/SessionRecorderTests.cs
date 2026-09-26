using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 识别结果落库（第九轮补）：会话与题目要**一次写全 NOT NULL 列**、要生成同步 op、
/// 要能被历史列表读回来。列名全部来自协议 schema 与一致性向量，不是手抄的。
/// </summary>
public sealed class SessionRecorderTests
{
    private static (LocalStore Store, QuizDatabase Database) NewStore(string deviceId = "windows-local")
    {
        var database = QuizDatabase.CreateFromProtocolSchema(":memory:");
        return (new LocalStore(database, deviceId), database);
    }

    private static IReadOnlyList<RecordedQuestion> Sample() =>
    [
        new RecordedQuestion(0, "第一题", "single", QuestionNo: "1", Choice: ["B"], Analysis: "解析一", Confidence: 0.9),
        new RecordedQuestion(1, "第二题", "subjective", AnswerText: "手写答案"),
    ];

    [Fact]
    public void Record_writes_the_session_and_every_question()
    {
        var (store, database) = NewStore();

        var sessionId = SessionRecorder.Record(
            store, "sha256:abc", "windows-local", Sample(), now: 1000,
            aiProvider: "openai-compatible", aiModel: "m", latencyMs: 123);

        var sessions = SessionRecorder.RecentSessions(database);
        var session = Assert.Single(sessions);
        Assert.Equal(sessionId, session.SessionId);
        Assert.Equal("sha256:abc", session.ImageHash);
        Assert.Equal(2, session.QuestionCount);
        Assert.Equal(123, session.LatencyMs);

        var questions = SessionRecorder.QuestionsOf(database, sessionId);
        Assert.Equal(2, questions.Count);
        Assert.Equal("第一题", questions[0].Stem);
        Assert.Equal(["B"], questions[0].Choice);       // 选择题的答案在 choice_json 里
        Assert.Equal("手写答案", questions[1].AnswerText);
        Assert.Equal(0, questions[0].Ordinal);
        Assert.Equal(1, questions[1].Ordinal);
    }

    [Fact]
    public void Record_generates_sync_ops_so_the_phone_can_pull_them()
    {
        var (store, _) = NewStore();

        SessionRecorder.Record(store, "sha256:abc", "windows-local", Sample(), now: 1000);

        var ops = store.LocalOpsSince(0);
        Assert.Equal(3, ops.Count);                     // 1 个 session + 2 个 question
        Assert.Contains(ops, op => op.Entity == SyncEntities.Session);
        Assert.Equal(2, ops.Count(op => op.Entity == SyncEntities.Question));
    }

    [Fact]
    public void Questions_come_back_in_ordinal_order()
    {
        var (store, database) = NewStore();
        var scrambled = new List<RecordedQuestion>
        {
            new(2, "第三题", "blank"),
            new(0, "第一题", "blank"),
            new(1, "第二题", "blank"),
        };

        var sessionId = SessionRecorder.Record(store, "sha256:x", "windows-local", scrambled, now: 1);

        Assert.Equal(["第一题", "第二题", "第三题"],
            SessionRecorder.QuestionsOf(database, sessionId).Select(q => q.Stem));
    }

    [Fact]
    public void Soft_deleted_sessions_are_not_listed()
    {
        var (store, database) = NewStore();
        var sessionId = SessionRecorder.Record(store, "sha256:a", "windows-local", Sample(), now: 1000);
        Assert.Single(SessionRecorder.RecentSessions(database));      // 删之前看得到

        store.DeleteLocal(SyncEntities.Session, sessionId, deletedAt: 2000);

        Assert.Empty(SessionRecorder.RecentSessions(database));       // 软删之后不在列表里
    }

    [Fact]
    public void Broken_choice_json_does_not_break_the_history_page()
    {
        var (store, database) = NewStore();
        var sessionId = SessionRecorder.Record(store, "sha256:a", "windows-local", Sample(), now: 1000);

        // 脏数据（比如别的端写坏的）不该让整页打不开。
        using (var command = database.Connection.CreateCommand())
        {
            command.CommandText = "UPDATE questions SET choice_json = '不是 JSON' WHERE session_id = $s";
            command.Parameters.AddWithValue("$s", sessionId);
            command.ExecuteNonQuery();
        }

        var questions = SessionRecorder.QuestionsOf(database, sessionId);
        Assert.Equal(2, questions.Count);
        Assert.Empty(questions[0].Choice!);
    }
}
