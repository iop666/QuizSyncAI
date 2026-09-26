using QuizSync.Data;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 图片文件清理（`maxFiles ≤ 0` = 不设限；`keep` 里的 hash 永不删）。
/// 语义与 Dart 侧 `pruneImageFiles` 逐条对齐。
/// </summary>
public sealed class ImagePrunerTests
{
    private static QuizDatabase NewDatabase() => QuizDatabase.CreateFromProtocolSchema(":memory:");

    /// <summary>插一条 images 行：created_at 用来定剪枝顺序（NOT NULL 列都要给）。</summary>
    private static void InsertImage(QuizDatabase database, string hash, long createdAt, string? localPath)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText =
            "INSERT INTO images (hash, size, mime, width, height, created_at, uploaded_by, local_path) " +
            "VALUES ($hash, 1024, 'image/jpeg', 100, 100, $at, 'test-device', $path)";
        command.Parameters.AddWithValue("$hash", hash);
        command.Parameters.AddWithValue("$at", createdAt);
        command.Parameters.AddWithValue("$path", (object?)localPath ?? DBNull.Value);
        command.ExecuteNonQuery();
    }

    private static string? LocalPath(QuizDatabase database, string hash)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT local_path FROM images WHERE hash = $hash";
        command.Parameters.AddWithValue("$hash", hash);
        var value = command.ExecuteScalar();
        return value is null or DBNull ? null : (string)value;
    }

    private static string PathOf(string hash) => $"C:/cache/{hash}.jpg";

    [Fact]
    public async Task Zero_or_negative_limit_means_no_pruning()
    {
        using var database = NewDatabase();
        for (var i = 0; i < 5; i++)
        {
            InsertImage(database, $"h{i}", i, PathOf($"h{i}"));
        }

        var deleted = new List<string>();
        var pruned = await ImagePruner.PruneAsync(
            database, PathOf, maxFiles: 0, onDelete: path => { deleted.Add(path); return Task.CompletedTask; });

        Assert.Equal(0, pruned);
        Assert.Empty(deleted);
        Assert.Equal(PathOf("h0"), LocalPath(database, "h0"));
    }

    [Fact]
    public async Task Under_the_limit_nothing_is_touched()
    {
        using var database = NewDatabase();
        InsertImage(database, "h0", 1, PathOf("h0"));
        InsertImage(database, "h1", 2, PathOf("h1"));

        var pruned = await ImagePruner.PruneAsync(database, PathOf, maxFiles: 2);

        Assert.Equal(0, pruned);
        Assert.NotNull(LocalPath(database, "h0"));
    }

    [Fact]
    public async Task Oldest_files_are_deleted_first_and_unlinked()
    {
        using var database = NewDatabase();
        for (var i = 0; i < 5; i++)
        {
            InsertImage(database, $"h{i}", i, PathOf($"h{i}"));
        }

        var deleted = new List<string>();
        var pruned = await ImagePruner.PruneAsync(
            database, PathOf, maxFiles: 3, onDelete: path => { deleted.Add(path); return Task.CompletedTask; });

        Assert.Equal(2, pruned);
        Assert.Equal([PathOf("h0"), PathOf("h1")], deleted); // 最旧的两个
        Assert.Null(LocalPath(database, "h0"));
        Assert.Null(LocalPath(database, "h1"));
        Assert.Equal(PathOf("h2"), LocalPath(database, "h2"));
        Assert.Equal(PathOf("h4"), LocalPath(database, "h4"));
    }

    [Fact]
    public async Task Kept_hashes_are_never_pruned_even_if_oldest()
    {
        using var database = NewDatabase();
        for (var i = 0; i < 4; i++)
        {
            InsertImage(database, $"h{i}", i, PathOf($"h{i}"));
        }

        var deleted = new List<string>();
        // h0 是最旧的，但它在离线队列里「保住」→ 应改剪 h1。
        var pruned = await ImagePruner.PruneAsync(
            database, PathOf, maxFiles: 2,
            onDelete: path => { deleted.Add(path); return Task.CompletedTask; },
            keep: new HashSet<string>(StringComparer.Ordinal) { "h0" });

        Assert.Equal(1, pruned);
        Assert.Equal([PathOf("h1")], deleted);
        Assert.Equal(PathOf("h0"), LocalPath(database, "h0"));
        Assert.Null(LocalPath(database, "h1"));
    }

    [Fact]
    public async Task Delete_failure_still_unlinks_so_it_is_not_retried_forever()
    {
        using var database = NewDatabase();
        InsertImage(database, "h0", 1, PathOf("h0"));
        InsertImage(database, "h1", 2, PathOf("h1"));

        var pruned = await ImagePruner.PruneAsync(
            database, PathOf, maxFiles: 1,
            onDelete: _ => Task.FromException(new IOException("文件被占用")));

        Assert.Equal(1, pruned);
        Assert.Null(LocalPath(database, "h0")); // 关联断了，下一轮不会再试
        Assert.NotNull(LocalPath(database, "h1"));
    }

    [Fact]
    public async Task Rows_without_local_path_do_not_count_toward_the_limit()
    {
        using var database = NewDatabase();
        InsertImage(database, "gone", 1, localPath: null);
        InsertImage(database, "h1", 2, PathOf("h1"));
        InsertImage(database, "h2", 3, PathOf("h2"));

        var pruned = await ImagePruner.PruneAsync(database, PathOf, maxFiles: 2);

        Assert.Equal(0, pruned); // 只剩两张有本地文件的，正好在上限内
        Assert.NotNull(LocalPath(database, "h1"));
    }

    [Fact]
    public void Set_local_path_writes_and_clears()
    {
        using var database = NewDatabase();
        InsertImage(database, "h0", 1, localPath: null);
        ImagePruner.SetLocalPath(database, "h0", "C:/cache/h0.jpg");
        Assert.Equal("C:/cache/h0.jpg", LocalPath(database, "h0"));
        ImagePruner.SetLocalPath(database, "h0", null);
        Assert.Null(LocalPath(database, "h0"));
    }
}
