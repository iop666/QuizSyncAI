using System.Text.Json;
using System.Text.Json.Nodes;

namespace QuizSync.Data;

/// <summary>
/// 同步 op（协议冻结形态，见 `spec/06-sync.md`）。`Fields` 的键是**数据库列名**。
/// </summary>
public sealed record SyncOp(
    string OpId,
    string DeviceId,
    long Lamport,
    string Entity,
    string EntityId,
    string OpType,
    IReadOnlyDictionary<string, object?> Fields,
    long CreatedAt)
{
    public JsonObject ToJson()
    {
        var fields = new JsonObject();
        foreach (var (key, value) in Fields)
        {
            fields[key] = value switch
            {
                null => null,
                string s => JsonValue.Create(s),
                long l => JsonValue.Create(l),
                int i => JsonValue.Create((long)i),
                double d => JsonValue.Create(d),
                bool b => JsonValue.Create(b),
                _ => JsonValue.Create(value.ToString()),
            };
        }

        return new JsonObject
        {
            ["op_id"] = OpId,
            ["device_id"] = DeviceId,
            ["lamport"] = Lamport,
            ["entity"] = Entity,
            ["entity_id"] = EntityId,
            ["op_type"] = OpType,
            ["fields_json"] = fields,
            ["created_at"] = CreatedAt,
        };
    }
}

public static class SyncEntities
{
    public const string Session = "session";
    public const string Question = "question";
    public const string Collection = "collection";
    public const string SessionImage = "session_image";
}

public static class SyncOpTypes
{
    public const string Upsert = "upsert";
    public const string Delete = "delete";
}

/// <summary>
/// Lamport 时钟。规则（与 Dart 参考实现一致）：
/// - 本地每次写就 `Tick()`（**无条件 +1**）；
/// - 收到对端 op 时 `Observe(remote)` → `max(本地, 对端) + 1`；
/// - 启动时从 `MAX(lamport)` 恢复。
/// </summary>
public sealed class LamportClock
{
    private readonly object _gate = new();
    private long _value;

    public LamportClock(long initial = 0) => _value = initial;

    public long Value
    {
        get
        {
            lock (_gate)
            {
                return _value;
            }
        }
    }

    public long Tick()
    {
        lock (_gate)
        {
            return ++_value;
        }
    }

    public long Observe(long remote)
    {
        lock (_gate)
        {
            _value = Math.Max(_value, remote) + 1;
            return _value;
        }
    }

    /// <summary>从库里恢复（`MAX(lamport)`，主机与客户端同口径）。</summary>
    public static LamportClock Restore(QuizDatabase database)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT COALESCE(MAX(lamport), 0) FROM sync_ops";
        var value = Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
        return new LamportClock(value);
    }
}

/// <summary>字段时钟：`{字段: {"l": lamport, "d": deviceId}}`。</summary>
public sealed record FieldClock(long Lamport, string Device)
{
    /// <summary>(lamport, device_id) 严格大于才赢；**相等即判负**。</summary>
    public bool Loses(long lamport, string device)
    {
        var byLamport = lamport.CompareTo(Lamport);
        return byLamport != 0 ? byLamport <= 0 : string.CompareOrdinal(device, Device) <= 0;
    }
}

public static class FieldClocks
{
    public static Dictionary<string, FieldClock> Parse(string? raw)
    {
        var clocks = new Dictionary<string, FieldClock>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(raw))
        {
            return clocks;
        }

        var node = JsonNode.Parse(raw) as JsonObject;
        if (node is null)
        {
            return clocks;
        }

        foreach (var (field, value) in node)
        {
            if (value is JsonObject clock)
            {
                clocks[field] = new FieldClock(
                    clock["l"]?.GetValue<long>() ?? 0L,
                    clock["d"]?.ToString() ?? string.Empty);
            }
        }

        return clocks;
    }

    public static string Encode(IReadOnlyDictionary<string, FieldClock> clocks)
    {
        var node = new JsonObject();
        foreach (var (field, clock) in clocks)
        {
            node[field] = new JsonObject { ["l"] = clock.Lamport, ["d"] = clock.Device };
        }

        return node.ToJsonString();
    }
}
