namespace QuizSync.Data;

/// <summary>
/// 本地图片文件清理：超过 <c>maxFiles</c> 时**删除最旧的文件并把 `local_path` 置 NULL**
/// （文本结果与元数据永久保留）。真正的删除动作由宿主注入（同步层保持无 I/O）。
///
/// 两条与 Dart 侧逐字一致的关键语义：
/// - `maxFiles &lt;= 0` 表示**不设限**；
/// - <c>keep</c> 里的 hash **永不删除** —— 安卓离线队列里的任务补跑时必须还能从磁盘取到
///   原图，而队列上限与本地上限是同一个量级，按时间剪最旧会先把队首任务的原图剪掉。
/// </summary>
public static class ImagePruner
{
    public const int DefaultMaxFiles = 200;

    /// <summary>返回真正被剪掉的文件数（删除失败也算：关联已经断开）。</summary>
    public static async Task<int> PruneAsync(
        QuizDatabase database,
        Func<string, string> pathOf,
        int maxFiles = DefaultMaxFiles,
        Func<string, Task>? onDelete = null,
        IReadOnlySet<string>? keep = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(database);
        ArgumentNullException.ThrowIfNull(pathOf);

        if (maxFiles <= 0)
        {
            return 0;
        }

        var candidates = new List<string>();
        using (var command = database.Connection.CreateCommand())
        {
            command.CommandText =
                "SELECT hash FROM images WHERE local_path IS NOT NULL ORDER BY created_at ASC";
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var hash = reader.GetString(0);
                if (keep is not null && keep.Contains(hash))
                {
                    continue;
                }

                candidates.Add(hash);
            }
        }

        if (candidates.Count <= maxFiles)
        {
            return 0;
        }

        var excess = candidates.Count - maxFiles;
        for (var i = 0; i < excess; i++)
        {
            var hash = candidates[i];
            if (onDelete is not null)
            {
                try
                {
                    await onDelete(pathOf(hash)).ConfigureAwait(false);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    // 删除失败（被占用 / 没权限）也要断开关联，否则每轮都会重复尝试同一个文件。
                }
            }

            SetLocalPath(database, hash, null);
        }

        return excess;
    }

    /// <summary>写入或清除某个 hash 的本地路径（本列是**本地专属**，不进同步 op）。</summary>
    public static void SetLocalPath(QuizDatabase database, string hash, string? localPath)
    {
        using var command = database.Connection.CreateCommand();
        command.CommandText = "UPDATE images SET local_path = $path WHERE hash = $hash";
        command.Parameters.AddWithValue("$path", (object?)localPath ?? DBNull.Value);
        command.Parameters.AddWithValue("$hash", hash);
        command.ExecuteNonQuery();
    }
}
