using System.Text.Json.Nodes;
using QuizSync.Core;
using QuizSync.Data;
using QuizSync.Provider;
using QuizSync.ServerBridge;

namespace QuizSync.Provider.Cli;

/// <summary>
/// Provider 的命令行入口（计划 §7.2/§7.3 的 `--headless`）。
///
/// 现在落地的是**自检**这一条：它把「能不能找到主机、控制面是否可用、本地库与截图是否正常」
/// 一次问清楚并按 JSON 输出 —— 无界面跑得起来，也是后续「无界面识别」那条链路的骨架。
/// </summary>
public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || args.Contains("help") || args.Contains("--help"))
        {
            PrintHelp();
            return args.Length == 0 ? 1 : 0;
        }

        var json = args.Contains("--json");
        var dataDir = ValueOf(args, "--data") ?? DefaultDataDirectory();

        try
        {
            return args[0] switch
            {
                "doctor" => await DoctorAsync(dataDir, json).ConfigureAwait(false),
                "analyze" => await AnalyzeAsync(dataDir, json, args).ConfigureAwait(false),
                "version" => PrintVersion(json),
                _ => Unknown(args[0]),
            };
        }
        catch (Exception error)
        {
            // 不吞异常：无界面模式下日志就是唯一的现场。
            Console.Error.WriteLine($"失败：{error.Message}");
            return 2;
        }
    }

    /// <summary>
    /// `analyze`：**截屏 → AI → 解析 → 打印**，无界面跑通「Windows 单机闭环」的那条链
    /// （计划 Phase 5 的 `--headless`）。原先这条链在 C# 上接不起来 —— 缺「截屏 → JPEG」，
    /// 本轮补上 `ScreenJpeg`。
    ///
    /// 配置走参数或环境变量，**都不给就用本地默认值**：
    /// `--ai-url`/`QS_AI_BASE_URL`、`--ai-key`/`QS_AI_API_KEY`、`--ai-model`/`QS_AI_MODEL`、
    /// `--ai-provider`/`QS_AI_PROVIDER`。`--no-hide` 关掉「拍之前先藏自己的窗口」。
    /// </summary>
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static async Task<int> AnalyzeAsync(string dataDir, bool json, string[] args)
    {
        var config = new AiConfig
        {
            ProviderId = ValueOf(args, "--ai-provider") ?? Environment.GetEnvironmentVariable("QS_AI_PROVIDER") ?? "openai-compatible",
            BaseUrl = ValueOf(args, "--ai-url") ?? Environment.GetEnvironmentVariable("QS_AI_BASE_URL") ?? string.Empty,
            ApiKey = ValueOf(args, "--ai-key") ?? Environment.GetEnvironmentVariable("QS_AI_API_KEY") ?? string.Empty,
            Model = ValueOf(args, "--ai-model") ?? Environment.GetEnvironmentVariable("QS_AI_MODEL") ?? string.Empty,
        };

        var hide = !args.Contains("--no-hide");
        var shot = ScreenJpeg.Capture(hide ? AppWindowScope.Title : null);
        if (shot is null)
        {
            Console.Error.WriteLine("截屏失败：拿不到屏幕尺寸。");
            return 2;
        }

        Directory.CreateDirectory(dataDir);
        using var database = QuizDatabase.CreateFromProtocolSchema(Path.Combine(dataDir, "quizsync.db"));
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(config.TimeoutSeconds + 30) };
        var engine = new AnalysisEngine(
            new HttpAiProvider(config.ProviderId, http),
            new AnalysisCache(database),
            new QuotaGuard(database),
            deviceId: "windows-local");

        var outcome = await engine.AnalyzeImageAsync(shot.Jpeg, shot.ImageHash, config).ConfigureAwait(false);

        var report = new JsonObject
        {
            ["image"] = new JsonObject
            {
                ["sha256"] = shot.ImageHash,
                ["width"] = shot.Width,
                ["height"] = shot.Height,
                ["source_width"] = shot.SourceWidth,
                ["source_height"] = shot.SourceHeight,
                ["bytes"] = shot.Jpeg.Length,
            },
            ["provider"] = config.ProviderId,
            ["model"] = config.Model,
            ["from_cache"] = outcome.FromCache,
            ["parse_failed"] = outcome.ParseFailed,
            ["latency_ms"] = outcome.LatencyMs,
            ["provider_calls"] = outcome.ProviderCalls,
            ["error_code"] = outcome.ErrorCode,
            ["error_message"] = outcome.ErrorMessage,
            ["question_count"] = outcome.Questions.Count,
            ["questions"] = new JsonArray([.. outcome.Questions.Select(q => (JsonNode)new JsonObject
            {
                ["question_no"] = q.QuestionNo,
                ["type"] = q.Type.ToString(),
                ["stem"] = q.Stem,
                ["answer"] = q.AnswerText,
                ["choice"] = new JsonArray([.. q.Choice.Select(c => (JsonNode)c)]),
                ["need_review"] = q.NeedReview,
                ["confidence"] = q.Confidence,
            })]),
        };

        Console.WriteLine(report.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = !json }));
        return outcome.ErrorCode is null ? 0 : 2;
    }

    private static async Task<int> DoctorAsync(string dataDir, bool json)
    {
        var report = new JsonObject
        {
            ["data_dir"] = dataDir,
            ["data_dir_exists"] = Directory.Exists(dataDir),
        };

        // 1) 主机：探活 + 控制面。
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        var probe = await new HostDiscovery(http).ProbeAsync().ConfigureAwait(false);
        report["host"] = probe is null
            ? null
            : new JsonObject
            {
                ["base_url"] = probe.BaseUrl,
                ["port"] = probe.Port,
                ["protocol_version"] = probe.ProtocolVersion,
                ["server_device_id"] = probe.ServerDeviceId,
            };

        var controlToken = HostControl.FindControlToken(dataDir);
        report["control_token_present"] = controlToken is not null;
        if (probe is not null && controlToken is not null)
        {
            try
            {
                var code = await new HostControl(probe.BaseUrl, controlToken, http).PairCodeAsync().ConfigureAwait(false);
                report["pairing_code"] = code?["code"]?.ToString();
            }
            catch (HostException error)
            {
                report["pairing_code_error"] = error.Code;
            }
        }

        // 2) 本地库：能开就报一下表数量（顺便证明 schema 在）。
        report["local_db"] = TryLocalDb(dataDir, out var dbNote) ? "ok" : "missing";
        if (dbNote is not null)
        {
            report["local_db_note"] = dbNote;
        }

        // 3) 截屏：真截一小块，证明 GDI 通路可用。
        var shot = ScreenCapture.CaptureRegion(0, 0, 8, 8);
        report["capture"] = shot is null ? "failed" : $"{shot.Width}x{shot.Height}";

        // 4) AI 配置：只报「有没有 key」，**绝不打印 key 本身**。
        var configPath = Path.Combine(dataDir, "ai-config.json");
        report["ai_config_present"] = File.Exists(configPath);
        report["prompt_version"] = Prompt.ComputePromptVersion();

        if (json)
        {
            Console.WriteLine(report.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        }
        else
        {
            Console.WriteLine("QuizSync Provider 自检");
            Console.WriteLine($"  数据目录   {dataDir}（{(Directory.Exists(dataDir) ? "存在" : "不存在")}）");
            Console.WriteLine($"  主机       {(probe is null ? "未发现" : $"{probe.BaseUrl}（协议 {probe.ProtocolVersion}）")}");
            Console.WriteLine($"  控制令牌   {(controlToken is null ? "无" : "已找到")}");
            Console.WriteLine($"  本地库     {report["local_db"]}");
            Console.WriteLine($"  截屏       {report["capture"]}");
            Console.WriteLine($"  提示词版本 {report["prompt_version"]}");
        }

        // 一个都没齐才算失败：自检的价值在于「一眼看出缺哪一块」。
        return probe is not null || report["local_db"]?.ToString() == "ok" || shot is not null ? 0 : 1;
    }

    private static bool TryLocalDb(string dataDir, out string? note)
    {
        note = null;
        var path = Path.Combine(dataDir, "quizsync.db");
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            using var database = QuizDatabase.OpenExisting(path);
            using var command = database.Connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table'";
            var tables = Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
            note = $"{tables} 张表";
            return true;
        }
        catch (Microsoft.Data.Sqlite.SqliteException error)
        {
            note = error.Message;
            return false;
        }
    }

    private static int PrintVersion(bool json)
    {
        Console.WriteLine(json
            ? new JsonObject { ["product"] = "QuizSync AI", ["component"] = "provider", ["protocol"] = "2.0.0" }.ToJsonString()
            : "QuizSync AI Provider（协议 2.0.0）");
        return 0;
    }

    private static int Unknown(string command)
    {
        Console.Error.WriteLine($"未知命令：{command}（用 --help 看用法）");
        return 1;
    }

    private static string? ValueOf(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    private static string DefaultDataDirectory() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuizSyncAI");

    private static void PrintHelp() => Console.WriteLine("""
        QuizSync AI Provider（无界面）

          doctor [--data <目录>] [--json]   自检：主机探活、控制面、本地库、截屏、提示词版本
          version [--json]                 打印组件与协议版本
          help                             本帮助

        退出码：0 = 至少有一块可用；1 = 用法错误；2 = 运行期失败（stderr 有原因）
        """);
}
