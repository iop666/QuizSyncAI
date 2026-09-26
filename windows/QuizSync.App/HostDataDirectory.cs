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
