using Microsoft.Data.Sqlite;

namespace QuizSync.Data;

/// <summary>
/// 本地库（Windows 端）。表结构**直接执行协议仓的 `schema/schema-v1.sql`**：
/// 手抄一份就有两个真相，早晚漂移（Android 侧的 Kotlin 内核也是这么做的）。
///
/// 两条实测前提：
/// - 那份 DDL **不是幂等的**（索引是裸 `CREATE INDEX`），对既有库再跑一遍会抛
///   `index ... already exists` —— 所以「首次建库」与「打开既有库」是两条路；
/// - `Microsoft.Data.Sqlite` 的一条命令**可以带多条语句**（与 AndroidX 的
///   `execSQL` 不同），所以这里不需要切分器。
/// </summary>
public sealed class QuizDatabase : IDisposable
{
    private readonly SqliteConnection _connection;

    private QuizDatabase(SqliteConnection connection) => _connection = connection;

    public SqliteConnection Connection => _connection;

    /// <summary>首次建库（执行协议 DDL）。[path] 传 `:memory:` 时是内存库。</summary>
    public static QuizDatabase Create(string path, string schemaSql)
    {
        var database = Connect(path);
        using var command = database._connection.CreateCommand();
        command.CommandText = schemaSql;
        command.ExecuteNonQuery();
        return database;
    }

    /// <summary>从协议仓的 schema 文件建库。</summary>
    public static QuizDatabase CreateFromProtocolSchema(string path) =>
        Create(path, File.ReadAllText(Path.Combine(ProtocolDirectory(), "schema", "schema-v1.sql")));

    /// <summary>打开一个**已经建好**的库（不执行 DDL）。</summary>
    public static QuizDatabase OpenExisting(string path) => Connect(path);

    /// <summary>
    /// 协议仓的位置：环境变量 `QS_PROTOCOL_DIR`，否则从当前目录往上找同级的
    /// `QuizSyncProtocol`。找不到就**抛**（不静默退化）。
    /// </summary>
    public static string ProtocolDirectory()
    {
        var configured = Environment.GetEnvironmentVariable("QS_PROTOCOL_DIR");
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(configured))
        {
            candidates.Add(configured);
        }

        var probe = new DirectoryInfo(AppContext.BaseDirectory);
        while (probe is not null)
        {
            candidates.Add(Path.Combine(probe.FullName, "QuizSyncProtocol"));
            candidates.Add(Path.Combine(probe.FullName, "..", "QuizSyncProtocol"));
            probe = probe.Parent;
        }

        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(Path.Combine(full, "schema", "schema-v1.sql")))
            {
                return full;
            }
        }

        throw new FileNotFoundException(
            "找不到协议仓（需要 schema/schema-v1.sql）。可用环境变量 QS_PROTOCOL_DIR 指定。");
    }

    private static QuizDatabase Connect(string path)
    {
        var connectionString = path == ":memory:"
            ? $"Data Source=file:qs{Guid.NewGuid():N}?mode=memory&cache=shared"
            : new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadWriteCreate, Pooling = false }.ToString();
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        var database = new QuizDatabase(connection);
        database.Execute("PRAGMA foreign_keys=ON");
        if (path != ":memory:")
        {
            database.Execute("PRAGMA journal_mode=WAL");
        }

        return database;
    }

    /// <summary>
    /// 执行一段 SQL（建表 / PRAGMA / 迁移 / 测试播种用）。
    /// 业务读写请走 <see cref="LocalStore"/> 与 Repository —— 那里才有 op 生成与 LWW。
    /// </summary>
    public void Execute(string sql)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    public void Dispose() => _connection.Dispose();
}
