using System;
using System.IO;

namespace QuizSync.App;

/// <summary>
/// 服务端数据目录的解析（配对页要读 `control.token`，它就在那个目录里）。
///
/// **这里原先有个真 bug**：首屏写死了 <c>AppContext.BaseDirectory/userdata</c>，
/// 而服务端 CLI 的数据目录是**它自己的** base dir 下的 `userdata`
/// （`QuizSyncServer/src/QuizSync.Server.Cli/Program.cs`: <c>parsed.DataDirectory ?? Path.Combine(AppContext.BaseDirectory, "userdata")</c>）——
/// 两者根本不是同一个目录，所以「显示配对码」点下去**必然**读不到控制令牌。
/// 因为那个按钮此前从没被真点过一次，这个 bug 一直藏着；第五轮做配对页时才暴露。
///
/// 解析顺序（找到第一个含 `control.token` 的目录就算命中）：
/// ① 环境变量 `QS_SERVER_DATA`（显式指定，脚本与验证用）；
/// ② 本应用自己的 `userdata`（将来由应用内嵌/自带服务端时就是这里）。
///
/// **正确解法（记在 docs/DECISIONS.md，下一轮做）**：两端与服务端约定一个**共享数据目录**
/// （`%LOCALAPPDATA%\QuizSyncAI\userdata`），而不是各自 `AppContext.BaseDirectory`。
/// </summary>
public static class HostDataDirectory
{
    public const string OverrideVariable = "QS_SERVER_DATA";

    /// <summary>找过的所有候选目录（找不到时报给用户看，不给一句「失败了」了事）。</summary>
    public static IReadOnlyList<string> Candidates()
    {
        var list = new List<string>();
        var fromEnvironment = Environment.GetEnvironmentVariable(OverrideVariable);
        if (!string.IsNullOrWhiteSpace(fromEnvironment))
        {
            list.Add(fromEnvironment);
        }

        // **共享数据目录优先**（第二十三轮）：应用与服务端是两个 exe，
        // 各自用 `AppContext.BaseDirectory/userdata` 的话根本不在一个地方 ——
        // 实测后果是「连接设备/显示配对码/推送」全都读不到 control.token，
        // 而普通用户不会去设 `QS_SERVER_DATA`。所以约定一个双方都认的位置。
        list.Add(SharedLayout.ServerDirectory);

        // 老位置留作兜底（开发时直接在 exe 旁边跑）。
        list.Add(Path.Combine(AppContext.BaseDirectory, "userdata"));
        return list;
    }

    /// <summary>返回第一个含 `control.token` 的候选目录；都没有则 null。</summary>
    public static string? Find()
    {
        foreach (var candidate in Candidates())
        {
            if (File.Exists(Path.Combine(candidate, "control.token")))
            {
                return candidate;
            }
        }

        return null;
    }

    /// <summary>找不到时给用户看的话：把找过的目录与可操作的做法都写出来。</summary>
    public static string ExplainMissing()
    {
        var looked = string.Join("、", Candidates());
        return $"没找到服务端数据目录（找过：{looked}）。"
             + $"请先运行 QuizSync.Server.Cli run，或用环境变量 {OverrideVariable} 指向服务端的数据目录。";
    }
}

/// <summary>
/// **应用自己的**数据目录 —— 与上面那个「服务端数据目录」是两件事，别混。
///
/// 为什么必须分开（第八轮踩到）：`quizsync.db` 这个名字在两边都叫一样，但**结构不同** ——
/// 服务端的库是 11 张表（`devices`/`images`/`sync_ops`/`tasks`…，协议中转用的），
/// 客户端本地的库是协议 schema 的 **16 张表**（多出 `analysis_cache`、`questions`、
/// `sessions` 等本地表）。一开始我把应用的 `AnalysisCache` 指到了服务端目录，
/// 于是报 `no such column: prompt_version`（服务端的库压根没有 analysis_cache 表）。
///
/// 服务端目录**只用来读 `control.token`**（配对），本地库一律走这里。
/// </summary>
public static class SharedLayout
{
    /// <summary>
    /// 共享根：`%LOCALAPPDATA%\QuizSyncAI`。
    ///
    /// **为什么要它**（第二十二轮实测）：应用与服务端是两个 exe，各自用
    /// `AppContext.BaseDirectory/userdata` → 不在同一个地方 → 应用读不到服务端的 `control.token`，
    /// 于是「显示配对码 / 连接设备 / 推送」整条链对真实用户是**断的**
    /// （我之前的验证全靠 `QS_SERVER_DATA` 把它们接上，那是我开发时的私有手段）。
    /// </summary>
    public static string Root
    {
        get
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(local, "QuizSyncAI");
        }
    }

    /// <summary>服务端的数据目录（库 + `control.token`）。</summary>
    public static string ServerDirectory => Path.Combine(Root, "server");

    /// <summary>应用自己的数据目录（本地库 + `ai.json` + `device.token` + 水位）。</summary>
    public static string AppDirectory => Path.Combine(Root, "app");
}

public static class AppDataDirectory
{
    /// <summary>本地库目录（保证存在）。</summary>
    public static string Ensure()
    {
        var directory = SharedLayout.AppDirectory;
        Directory.CreateDirectory(directory);
        return directory;
    }

    /// <summary>本地库文件路径。</summary>
    public static string DatabasePath() => Path.Combine(Ensure(), "quizsync.db");
}
