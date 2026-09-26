using Microsoft.Data.Sqlite;
using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 建库/开库的语义（第八轮补的回归）。
///
/// 背景：协议 DDL **不幂等**（索引是裸 `CREATE INDEX`），所以「首次建库」与「打开既有库」
/// 是两条路。`CreateFromProtocolSchema` 被界面和 `Provider.Cli analyze` 当成日常入口用了，
/// 于是对既有库再跑一遍 DDL → `index idx_images_created already exists`。
/// 命令行没暴露是因为验证时每次换新目录；界面第一次跑就撞上（用的是已存在的服务端库）。
///
/// 测试刻意**不碰具体业务表**（不去猜列名）：这一条要钉的是「开两次会不会炸」。
/// </summary>
public sealed class QuizDatabaseLifecycleTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"qs-db-{Guid.NewGuid():N}.db");

    public void Dispose()
    {
        SqliteConnection.ClearAllPools();
        foreach (var suffix in new[] { "", "-wal", "-shm" })
        {
            var file = _path + suffix;
            if (File.Exists(file))
            {
                File.Delete(file);
            }
        }
    }

    private static long TableCount(QuizDatabase database)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table'";
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
    }

    [Fact]
    public void OpenOrCreate_creates_the_schema_on_first_use()
    {
        using var database = QuizDatabase.OpenOrCreate(_path);

        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='images'";
        Assert.Equal(1L, Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture));
    }

    [Fact]
    public void OpenOrCreate_is_idempotent_on_an_existing_database()
    {
        long created;
        using (var first = QuizDatabase.OpenOrCreate(_path))
        {
            created = TableCount(first);
        }

        // 这一句就是当初在界面上炸掉的那一步：对已有库再开一次。
        using var second = QuizDatabase.OpenOrCreate(_path);

        Assert.Equal(created, TableCount(second));
    }

    [Fact]
    public void CreateFromProtocolSchema_still_throws_on_an_existing_database()
    {
        // 把这个已知语义钉住：`Create…` **不是**日常入口（日常走 OpenOrCreate）。
        // 哪天协议 DDL 改成幂等了，这条会红 —— 那时应删掉它并简化 OpenOrCreate。
        using (QuizDatabase.OpenOrCreate(_path))
        {
        }

        Assert.ThrowsAny<SqliteException>(() => QuizDatabase.CreateFromProtocolSchema(_path));
    }

    [Fact]
    public void Failed_create_does_not_leak_the_connection()
    {
        // 建库失败后必须能删掉库文件 —— 否则失败的建库会一直占着它
        // （原来 `Create` 抛异常时不释放连接，实测连删除都失败）。
        using (QuizDatabase.OpenOrCreate(_path))
        {
        }

        Assert.ThrowsAny<SqliteException>(() => QuizDatabase.CreateFromProtocolSchema(_path));

        SqliteConnection.ClearAllPools();
        foreach (var suffix in new[] { "", "-wal", "-shm" })
        {
            var file = _path + suffix;
            if (File.Exists(file))
            {
                File.Delete(file); // 锁没释放的话这里会抛 IOException
            }
        }
    }
}
