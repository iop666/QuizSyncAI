using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// Phase 5 的地基：**本地写要生成 op、远端 op 要按 LWW 落地、两端最终收敛**。
///
/// 这些用例对着 `spec/06-sync.md` 与 `sync.ndjson` 的语义写，是 Windows 内核
/// 数据层的验收基线（与 Kotlin 侧的向量对拍同一批规则）。
/// </summary>
public sealed class LocalStoreTests
{
    /// <summary>建库用**协议仓的 schema**（与 Android 侧同一份 DDL，不手抄）。</summary>
    private static QuizDatabase NewDatabase() => QuizDatabase.CreateFromProtocolSchema(":memory:");

    private static LocalStore NewStore(string deviceId, out QuizDatabase database)
    {
        database = NewDatabase();
        return new LocalStore(database, deviceId);
    }

    private static Dictionary<string, object?> Question(string sessionId, string answer) => new()
    {
        ["session_id"] = sessionId,
        ["ordinal"] = 0L,
        ["stem"] = "题目",
        ["type"] = "single_choice",
        ["answer_text"] = answer,
        ["created_at"] = 1000L,
        ["updated_at"] = 1000L,
        ["updated_by"] = "test",
    };

    /// <summary>
    /// 新行的 op 必须带齐「NOT NULL 且无默认值」的列（questions 是 session_id /
    /// ordinal / created_at / updated_at / updated_by）—— 少一个，落库就会
    /// 抛 NOT NULL 约束失败。这是协议的一部分：缺列不许静默补假值。
    /// </summary>
    private static Dictionary<string, object?> NewQuestionFields(string answer) => new()
    {
        ["session_id"] = "s-1",
        ["ordinal"] = 0L,
        ["stem"] = "题",
        ["type"] = "single_choice",
        ["created_at"] = 1L,
        ["updated_at"] = 1L,
        ["updated_by"] = "test",
        ["answer_text"] = answer,
    };

    [Fact]
    public void WriteLocal_generates_op_with_only_changed_fields()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            var created = store.WriteLocal(SyncEntities.Question, "q-1", Question("s-1", "A"));
            Assert.NotNull(created);
            Assert.Equal(1L, created!.Lamport);
            Assert.Equal("q-1", created.EntityId);
            Assert.Equal(SyncOpTypes.Upsert, created.OpType);
            // fields_json 只装真正改动的字段（这里就是传进去的那几个）。
            Assert.Contains("answer_text", created.Fields.Keys);
            Assert.Contains("stem", created.Fields.Keys);
            Assert.DoesNotContain("analysis", created.Fields.Keys);

            // 同一句话再写一次：没有实际改动 → **不生成 op**（避免刷一堆空 op）。
            var again = store.WriteLocal(SyncEntities.Question, "q-1", Question("s-1", "A"));
            Assert.Null(again);

            // 改一个字段：只带那一个字段。
            var changed = store.WriteLocal(
                SyncEntities.Question, "q-1", new Dictionary<string, object?> { ["answer_text"] = "B" });
            Assert.NotNull(changed);
            Assert.Single(changed!.Fields);
            Assert.Equal("B", changed.Fields["answer_text"]);
            Assert.True(changed.Lamport > created.Lamport, "本地写要推进 Lamport");
        }
    }

    [Fact]
    public void WriteLocal_ignores_columns_outside_the_whitelist()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            var op = store.WriteLocal(
                SyncEntities.Question,
                "q-1",
                new Dictionary<string, object?> { ["session_id"] = "s-1", ["ordinal"] = 0L, ["stem"] = "题", ["type"] = "single_choice", ["created_at"] = 1L, ["updated_at"] = 1L, ["updated_by"] = "t", ["local_only_column"] = "不该进 op" });
            Assert.NotNull(op);
            Assert.DoesNotContain("local_only_column", op!.Fields.Keys);
        }
    }

    [Fact]
    public void Remote_op_lands_with_field_clocks_and_lww_blocks_older_writes()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            var remote = new SyncOp(
                "op-1", "android-local", 10, SyncEntities.Question, "q-1", SyncOpTypes.Upsert,
                NewQuestionFields("A"),
                1000);
            Assert.True(store.ApplyRemote(remote));

            var read = store.Read(SyncEntities.Question, "q-1");
            Assert.NotNull(read);
            Assert.Equal("A", read!.Value.Values["answer_text"]);
            Assert.Equal(10L, read.Value.Clocks["answer_text"].Lamport);
            Assert.Equal("android-local", read.Value.Clocks["answer_text"].Device);

            // 更低 lamport 的 op 改同一字段：判负，值不变。
            var stale = remote with
            {
                OpId = "op-2",
                Lamport = 9,
                Fields = new Dictionary<string, object?> { ["answer_text"] = "旧值" },
            };
            Assert.True(store.ApplyRemote(stale));
            Assert.Equal("A", store.Read(SyncEntities.Question, "q-1")!.Value.Values["answer_text"]);

            // 更高 lamport：赢。
            var newer = remote with
            {
                OpId = "op-3",
                Lamport = 11,
                Fields = new Dictionary<string, object?> { ["answer_text"] = "B" },
            };
            Assert.True(store.ApplyRemote(newer));
            Assert.Equal("B", store.Read(SyncEntities.Question, "q-1")!.Value.Values["answer_text"]);
        }
    }

    [Fact]
    public void Same_lamport_is_a_tie_and_device_id_breaks_it()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            var first = new SyncOp(
                "op-a", "android-local", 5, SyncEntities.Question, "q-1", SyncOpTypes.Upsert,
                NewQuestionFields("A"),
                1);
            store.ApplyRemote(first);

            // 同 lamport、device_id 更大 → 赢。
            var winner = first with { OpId = "op-b", DeviceId = "zz-device", Fields = new Dictionary<string, object?> { ["answer_text"] = "C" } };
            store.ApplyRemote(winner);
            Assert.Equal("C", store.Read(SyncEntities.Question, "q-1")!.Value.Values["answer_text"]);

            // 同 lamport、device_id 更小 → 判负。
            var loser = first with { OpId = "op-c", DeviceId = "aa-device", Fields = new Dictionary<string, object?> { ["answer_text"] = "D" } };
            store.ApplyRemote(loser);
            Assert.Equal("C", store.Read(SyncEntities.Question, "q-1")!.Value.Values["answer_text"]);

            // 同一条 op 重复投递 → 幂等（不重复记账）。
            Assert.False(store.ApplyRemote(winner));
        }
    }

    [Fact]
    public void Two_stores_converge_after_exchanging_ops()
    {
        var windows = NewStore("windows-local", out var windowsDb);
        var android = NewStore("android-local", out var androidDb);
        using (windowsDb)
        using (androidDb)
        {
            // 两端各自改不同字段。
            var opA = windows.WriteLocal(SyncEntities.Question, "q-1", Question("s-1", "A"));
            // 先让安卓侧拿到这条记录（新行必须带齐 NOT NULL 列），它再改自己的字段。
            android.ApplyRemote(opA!);
            var opB = android.WriteLocal(
                SyncEntities.Question, "q-1", new Dictionary<string, object?> { ["analysis"] = "安卓写的解析" });

            // 反向落地。
            windows.ApplyRemote(opB!);

            var onWindows = windows.Read(SyncEntities.Question, "q-1")!.Value.Values;
            var onAndroid = android.Read(SyncEntities.Question, "q-1")!.Value.Values;
            Assert.Equal("A", onWindows["answer_text"]);
            Assert.Equal("A", onAndroid["answer_text"]);
            Assert.Equal("安卓写的解析", onWindows["analysis"]);
            Assert.Equal("安卓写的解析", onAndroid["analysis"]);
        }
    }

    [Fact]
    public void Delete_is_a_tombstone_field_and_travels_as_an_op()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            store.WriteLocal(SyncEntities.Question, "q-1", Question("s-1", "A"));
            var deleted = store.DeleteLocal(SyncEntities.Question, "q-1", 5000);
            Assert.NotNull(deleted);
            Assert.Equal(SyncOpTypes.Delete, deleted!.OpType);
            Assert.Equal(5000L, deleted.Fields["deleted_at"]);
            Assert.Equal(5000L, store.Read(SyncEntities.Question, "q-1")!.Value.Values["deleted_at"]);
        }
    }

    [Fact]
    public void Lamport_clock_observes_remote_and_survives_restart()
    {
        var store = NewStore("windows-local", out var database);
        using (database)
        {
            store.WriteLocal(SyncEntities.Question, "q-1", Question("s-1", "A"));
            var before = store.Lamport;

            store.ApplyRemote(new SyncOp(
                "op-remote", "android-local", before + 100, SyncEntities.Question, "q-2", SyncOpTypes.Upsert,
                NewQuestionFields("对端"), 1));

            Assert.True(store.Lamport > before + 100, "收到远端 op 后本地时钟要越过它");

            // 重启（重新打开同一库）恢复的是 **MAX(sync_ops.lamport)** —— 一个安全下界，
            // 不是内存里那个「观察之后又 +1」的值（那个值本来就不持久化）。
            var restored = LamportClock.Restore(database);
            Assert.True(
                restored.Value == before + 100,
                $"恢复值 {restored.Value} 应当是日志里的最大 lamport {before + 100}");

            // 真正要保证的不变式：**本地下一次写的 lamport 大于日志里见过的所有 lamport**
            //（否则会和已发生的 op 撞号，LWW 的平局规则就会误判）。
            var next = store.WriteLocal(
                SyncEntities.Question, "q-1", new Dictionary<string, object?> { ["answer_text"] = "新值" });
            Assert.NotNull(next);
            var maxSeen = database.Connection.CreateCommand();
            maxSeen.CommandText = "SELECT MAX(lamport) FROM sync_ops WHERE op_id <> $id";
            maxSeen.Parameters.AddWithValue("$id", next!.OpId);
            var previousMax = Convert.ToInt64(maxSeen.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
            var greater = next.Lamport > previousMax;
            Assert.True(greater, $"本地写的 lamport（{next.Lamport}）必须大于见过的最大 lamport（{previousMax}）");
        }
    }
}
