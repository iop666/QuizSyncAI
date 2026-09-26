using Microsoft.Data.Sqlite;

namespace QuizSync.Data;

/// <summary>
/// 本地写路径 + 远端 op 落地（Windows 内核的数据层核心）。
///
/// 两条纪律：
/// - **本地每次写都必须生成 op**：只带**真正改动**的字段（`fields_json` 的语义），
///   lamport 取本地时钟 `Tick()`，并把每个改动字段的时钟记成 `(lamport, 本机 device_id)`；
/// - **落到本地的字段白名单**：`fields_json` 的键来自网络，直接拼 SQL 就是注入。
/// </summary>
public sealed class LocalStore
{
    private static readonly Dictionary<string, (string Table, string IdColumn, string[] Columns)> Entities = new(StringComparer.Ordinal)
    {
        [SyncEntities.Session] = ("sessions", "session_id",
        [
            "image_hash", "source_device", "status", "question_count", "cached", "collection_id",
            "created_at", "updated_at", "updated_by", "deleted_at", "task_id", "error_message", "latency_ms",
        ]),
        [SyncEntities.Question] = ("questions", "question_id",
        [
            "session_id", "ordinal", "question_no", "stem", "material", "type", "options_json", "choice_json",
            "answer_text", "analysis", "confidence", "need_review", "answer_in_image", "incomplete",
            "answer_guessed", "warnings_json", "analysis_edited", "answer_edited",
            "created_at", "updated_at", "updated_by", "deleted_at",
        ]),
        [SyncEntities.Collection] = ("collections", "collection_id",
        [
            "name", "created_at", "updated_at", "updated_by", "deleted_at",
        ]),
        [SyncEntities.SessionImage] = ("session_images", "session_image_id",
        [
            "session_id", "ordinal", "image_hash", "created_at", "deleted_at",
        ]),
    };

    private readonly QuizDatabase _database;
    private readonly LamportClock _clock;

    public LocalStore(QuizDatabase database, string deviceId, LamportClock? clock = null)
    {
        _database = database;
        DeviceId = deviceId;
        _clock = clock ?? LamportClock.Restore(database);
    }

    public string DeviceId { get; }

    public long Lamport => _clock.Value;

    /// <summary>
    /// 本地写一条实体：算改动、写行、生成 op。返回生成的 op（没有实际改动时返回 null）。
    /// </summary>
    public SyncOp? WriteLocal(string entity, string entityId, IReadOnlyDictionary<string, object?> fields, string opType = SyncOpTypes.Upsert)
    {
        if (!Entities.TryGetValue(entity, out var target))
        {
            throw new ArgumentException($"未知实体：{entity}", nameof(entity));
        }

        var (table, idColumn, columns) = target;
        var allowed = new HashSet<string>(columns, StringComparer.Ordinal);
        var (existing, clocks) = ReadRow(table, idColumn, entityId);

        // 只保留白名单里的列，并剔除「值没变」的字段（op 的 fields_json 只装真正改动的）。
        var changed = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (field, value) in fields)
        {
            if (!allowed.Contains(field))
            {
                continue;
            }

            if (existing is not null && ValuesEqual(existing.GetValueOrDefault(field), value))
            {
                continue;
            }

            changed[field] = value;
        }

        if (changed.Count == 0 && existing is not null)
        {
            return null;
        }

        var lamport = _clock.Tick();
        foreach (var field in changed.Keys)
        {
            clocks[field] = new FieldClock(lamport, DeviceId);
        }

        if (existing is null)
        {
            var names = new List<string> { idColumn };
            var values = new List<object?> { entityId };
            foreach (var (field, value) in changed)
            {
                names.Add(field);
                values.Add(value);
            }

            names.Add("lamport");
            values.Add(lamport);
            names.Add("field_clocks_json");
            values.Add(FieldClocks.Encode(clocks));

            using var insert = _database.Connection.CreateCommand();
            insert.CommandText =
                $"INSERT INTO {table} ({string.Join(", ", names)}) VALUES ({string.Join(", ", names.Select((_, i) => "$p" + i))})";
            for (var i = 0; i < values.Count; i++)
            {
                insert.Parameters.AddWithValue("$p" + i, values[i] ?? DBNull.Value);
            }

            insert.ExecuteNonQuery();
        }
        else
        {
            using var update = _database.Connection.CreateCommand();
            var sets = new List<string>();
            var index = 0;
            foreach (var (field, value) in changed)
            {
                sets.Add($"{field} = $w{index}");
                update.Parameters.AddWithValue("$w" + index, value ?? DBNull.Value);
                index++;
            }

            sets.Add("lamport = $lamport");
            sets.Add("field_clocks_json = $clocks");
            update.Parameters.AddWithValue("$lamport", lamport);
            update.Parameters.AddWithValue("$clocks", FieldClocks.Encode(clocks));
            update.Parameters.AddWithValue("$id", entityId);
            update.CommandText = $"UPDATE {table} SET {string.Join(", ", sets)} WHERE {idColumn} = $id";
            update.ExecuteNonQuery();
        }

        var op = new SyncOp(
            OpId: Guid.NewGuid().ToString(),
            DeviceId: DeviceId,
            Lamport: lamport,
            Entity: entity,
            EntityId: entityId,
            OpType: opType,
            Fields: changed,
            CreatedAt: DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

        InsertOpLog(op);
        return op;
    }

    /// <summary>删除 = 写 `deleted_at`（墓碑），同样生成 op 并受 LWW 约束。</summary>
    public SyncOp? DeleteLocal(string entity, string entityId, long deletedAt)
    {
        var isQuestion = entity == SyncEntities.Question;
        var fields = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["deleted_at"] = deletedAt,
        };
        if (isQuestion || entity == SyncEntities.Session)
        {
            fields["updated_at"] = deletedAt;
        }

        return WriteLocal(entity, entityId, fields, SyncOpTypes.Delete);
    }

    /// <summary>
    /// 应用对端 op（**逐字段 LWW**）。`op_id` 幂等；返回是否真的写入了新 op。
    /// </summary>
    public bool ApplyRemote(SyncOp op)
    {
        if (OpExists(op.OpId))
        {
            return false;
        }

        InsertOpLog(op);
        _clock.Observe(op.Lamport);

        if (!Entities.TryGetValue(op.Entity, out var target))
        {
            return true; // 未知实体只记账
        }

        var (table, idColumn, columns) = target;
        var allowed = new HashSet<string>(columns, StringComparer.Ordinal);
        var (existing, clocks) = ReadRow(table, idColumn, op.EntityId);

        var winners = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (field, value) in op.Fields)
        {
            if (!allowed.Contains(field))
            {
                continue;
            }

            if (clocks.TryGetValue(field, out var clock) && clock.Loses(op.Lamport, op.DeviceId))
            {
                continue;
            }

            winners[field] = value;
            clocks[field] = new FieldClock(op.Lamport, op.DeviceId);
        }

        // 行水位就存在 values 里的 `lamport` 列（ReadRow 会把除 field_clocks_json 外的列都读回来）。
        var rowLamport = existing is not null && existing.TryGetValue("lamport", out var lamportValue) && lamportValue is not null
            ? Convert.ToInt64(lamportValue, System.Globalization.CultureInfo.InvariantCulture)
            : 0L;
        var newLamport = Math.Max(rowLamport, op.Lamport);

        if (existing is null)
        {
            var names = new List<string> { idColumn };
            var values = new List<object?> { op.EntityId };
            foreach (var (field, value) in winners)
            {
                names.Add(field);
                values.Add(value);
            }

            names.Add("lamport");
            values.Add(newLamport);
            names.Add("field_clocks_json");
            values.Add(FieldClocks.Encode(clocks));

            using var insert = _database.Connection.CreateCommand();
            insert.CommandText =
                $"INSERT INTO {table} ({string.Join(", ", names)}) VALUES ({string.Join(", ", names.Select((_, i) => "$p" + i))})";
            for (var i = 0; i < values.Count; i++)
            {
                insert.Parameters.AddWithValue("$p" + i, values[i] ?? DBNull.Value);
            }

            insert.ExecuteNonQuery();
            return true;
        }

        if (winners.Count == 0)
        {
            return true; // 全部字段判负：不写行，但 op 已记账
        }

        using var update = _database.Connection.CreateCommand();
        var sets = new List<string>();
        var index = 0;
        foreach (var (field, value) in winners)
        {
            sets.Add($"{field} = $w{index}");
            update.Parameters.AddWithValue("$w" + index, value ?? DBNull.Value);
            index++;
        }

        sets.Add("lamport = $lamport");
        sets.Add("field_clocks_json = $clocks");
        update.Parameters.AddWithValue("$lamport", newLamport);
        update.Parameters.AddWithValue("$clocks", FieldClocks.Encode(clocks));
        update.Parameters.AddWithValue("$id", op.EntityId);
        update.CommandText = $"UPDATE {table} SET {string.Join(", ", sets)} WHERE {idColumn} = $id";
        update.ExecuteNonQuery();
        return true;
    }

    /// <summary>读出某实体的字段值 + 字段时钟（供测试与 Repository 用）。</summary>
    public (Dictionary<string, object?> Values, Dictionary<string, FieldClock> Clocks)? Read(string entity, string entityId)
    {
        if (!Entities.TryGetValue(entity, out var target))
        {
            throw new ArgumentException($"未知实体：{entity}", nameof(entity));
        }

        var (existing, clocks) = ReadRow(target.Table, target.IdColumn, entityId);
        return existing is null ? null : (existing, clocks);
    }

    /// <summary>本机发出的 op（推送用：`WHERE device_id = 本机 AND lamport > sent`）。</summary>
    public IReadOnlyList<SyncOp> LocalOpsSince(long sentLamport, int limit = 500)
    {
        var ops = new List<SyncOp>();
        using var command = _database.Connection.CreateCommand();
        command.CommandText = """
            SELECT op_id, device_id, lamport, entity, entity_id, op_type, fields_json, created_at
            FROM sync_ops WHERE device_id = $dev AND lamport > $since
            ORDER BY lamport ASC, op_id ASC LIMIT $limit
            """;
        command.Parameters.AddWithValue("$dev", DeviceId);
        command.Parameters.AddWithValue("$since", sentLamport);
        command.Parameters.AddWithValue("$limit", limit);
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            ops.Add(new SyncOp(
                OpId: reader.GetString(0),
                DeviceId: reader.GetString(1),
                Lamport: reader.GetInt64(2),
                Entity: reader.GetString(3),
                EntityId: reader.GetString(4),
                OpType: reader.GetString(5),
                Fields: ParseFields(reader.GetString(6)),
                CreatedAt: reader.GetInt64(7)));
        }

        return ops;
    }

    private static Dictionary<string, object?> ParseFields(string json)
    {
        var fields = new Dictionary<string, object?>(StringComparer.Ordinal);
        var node = System.Text.Json.Nodes.JsonNode.Parse(json) as System.Text.Json.Nodes.JsonObject;
        if (node is null)
        {
            return fields;
        }

        foreach (var (key, value) in node)
        {
            fields[key] = value switch
            {
                null => null,
                System.Text.Json.Nodes.JsonValue v when v.TryGetValue<string>(out var s) => s,
                System.Text.Json.Nodes.JsonValue v when v.TryGetValue<long>(out var l) => l,
                System.Text.Json.Nodes.JsonValue v when v.TryGetValue<double>(out var d) => d,
                _ => value.ToJsonString(),
            };
        }

        return fields;
    }

    private (Dictionary<string, object?>? Values, Dictionary<string, FieldClock> Clocks) ReadRow(
        string table, string idColumn, string id)
    {
        using var command = _database.Connection.CreateCommand();
        command.CommandText = $"SELECT * FROM {table} WHERE {idColumn} = $id";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        if (!reader.Read())
        {
            return (null, new Dictionary<string, FieldClock>(StringComparer.Ordinal));
        }

        var values = new Dictionary<string, object?>(StringComparer.Ordinal);
        string? clocksJson = null;
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var name = reader.GetName(i);
            if (name == "field_clocks_json")
            {
                clocksJson = reader.IsDBNull(i) ? null : reader.GetString(i);
                continue;
            }

            values[name] = reader.IsDBNull(i) ? null : reader.GetValue(i);
        }

        return (values, FieldClocks.Parse(clocksJson));
    }

    private bool OpExists(string opId)
    {
        using var command = _database.Connection.CreateCommand();
        command.CommandText = "SELECT 1 FROM sync_ops WHERE op_id = $id LIMIT 1";
        command.Parameters.AddWithValue("$id", opId);
        return command.ExecuteScalar() is not null;
    }

    private void InsertOpLog(SyncOp op)
    {
        using var command = _database.Connection.CreateCommand();
        command.CommandText = """
            INSERT OR IGNORE INTO sync_ops (op_id, device_id, lamport, entity, entity_id, op_type, fields_json, created_at)
            VALUES ($id, $dev, $lamport, $entity, $eid, $type, $fields, $at)
            """;
        command.Parameters.AddWithValue("$id", op.OpId);
        command.Parameters.AddWithValue("$dev", op.DeviceId);
        command.Parameters.AddWithValue("$lamport", op.Lamport);
        command.Parameters.AddWithValue("$entity", op.Entity);
        command.Parameters.AddWithValue("$eid", op.EntityId);
        command.Parameters.AddWithValue("$type", op.OpType);
        command.Parameters.AddWithValue("$fields", op.ToJson()["fields_json"]!.ToJsonString());
        command.Parameters.AddWithValue("$at", op.CreatedAt);
        command.ExecuteNonQuery();
    }

    private static bool ValuesEqual(object? left, object? right)
    {
        if (left is null && right is null)
        {
            return true;
        }

        if (left is null || right is null)
        {
            return false;
        }

        var leftText = left is string s ? s : Convert.ToString(left, System.Globalization.CultureInfo.InvariantCulture);
        var rightText = right is string t ? t : Convert.ToString(right, System.Globalization.CultureInfo.InvariantCulture);
        return string.Equals(leftText, rightText, StringComparison.Ordinal);
    }
}
