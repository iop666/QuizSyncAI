using System.Diagnostics;
using System.Text.Json.Nodes;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 无界面入口（`--headless`）的自检：**真的把 CLI 跑起来**（另一个进程），
/// 对着真实 C# Server 看它报的 JSON 对不对。
/// </summary>
public sealed class ProviderCliTests
{
    private static string ServerDll()
    {
        var configured = Environment.GetEnvironmentVariable("QS_SERVER_DLL");
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(configured))
        {
            candidates.Add(configured);
        }

        var probe = new DirectoryInfo(AppContext.BaseDirectory);
        while (probe is not null)
        {
            candidates.Add(Path.Combine(probe.FullName, "QuizSyncServer", "src", "QuizSync.Server.Cli", "bin", "Release", "publish", "QuizSync.Server.Cli.dll"));
            probe = probe.Parent;
        }

        return candidates.FirstOrDefault(File.Exists)
            ?? throw new FileNotFoundException("找不到服务端产物（见 ServerBridgeEndToEndTests 的说明）");
    }

    private static string CliDll()
    {
        var probe = new DirectoryInfo(AppContext.BaseDirectory);
        while (probe is not null)
        {
            var candidate = Path.Combine(probe.FullName, "QuizSync.Provider.Cli", "bin", "Debug", "net10.0", "QuizSync.Provider.Cli.dll");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            probe = probe.Parent;
        }

        throw new FileNotFoundException("找不到 Provider CLI 产物（先 dotnet build）");
    }

    private static string Dotnet() => Environment.GetEnvironmentVariable("QS_DOTNET")
        ?? throw new InvalidOperationException("请设置 QS_DOTNET 指向 dotnet 可执行文件");

    private static int FreePort()
    {
        var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        listener.Start();
        var port = ((System.Net.IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    private static (string Output, int ExitCode) RunCli(params string[] args)
    {
        var info = new ProcessStartInfo(Dotnet()) { RedirectStandardOutput = true, RedirectStandardError = true };
        info.ArgumentList.Add(CliDll());
        foreach (var arg in args)
        {
            info.ArgumentList.Add(arg);
        }

        using var process = Process.Start(info)!;
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit(30_000);
        return (output + error, process.ExitCode);
    }

    [Fact]
    public void Version_and_help_work_without_any_configuration()
    {
        var (versionOut, versionCode) = RunCli("version", "--json");
        Assert.Equal(0, versionCode);
        var json = JsonNode.Parse(versionOut)!;
        Assert.Equal("provider", json["component"]!.ToString());
        Assert.Equal("2.0.0", json["protocol"]!.ToString());

        var (helpOut, helpCode) = RunCli("--help");
        Assert.Equal(0, helpCode);
        Assert.Contains("doctor", helpOut, StringComparison.Ordinal);
    }

    [Fact]
    public void Unknown_command_fails_loudly()
    {
        var (output, code) = RunCli("nonsense");
        Assert.Equal(1, code);
        Assert.Contains("未知命令", output, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Doctor_against_a_real_server_reports_host_control_plane_and_local_sources()
    {
        var dataDir = Directory.CreateTempSubdirectory("qs-provider-cli-").FullName;
        var port = FreePort();
        using var server = Process.Start(new ProcessStartInfo(Dotnet())
        {
            ArgumentList = { ServerDll(), "run", "--port", port.ToString(), "--data", dataDir },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;

        try
        {
            // 等主机起来（最多 20 秒）。
            var healthy = false;
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            var deadline = DateTimeOffset.UtcNow.AddSeconds(20);
            while (DateTimeOffset.UtcNow < deadline && !healthy)
            {
                healthy = await new QuizSync.ServerBridge.HostDiscovery(http)
                    .ProbePortAsync("127.0.0.1", port) is not null;
                if (!healthy)
                {
                    await Task.Delay(250);
                }
            }

            Assert.True(healthy, "服务端没起来");

            // CLI 只探默认端口段（8765+），所以这里直接断言「本机数据目录那块」是准的；
            // 主机发现走的是同一条 HostDiscovery 代码路径（已由 Bridge 的 E2E 覆盖）。
            var (output, code) = RunCli("doctor", "--data", dataDir, "--json");
            Assert.Equal(0, code);

            var report = JsonNode.Parse(output.Substring(output.IndexOf('{', StringComparison.Ordinal)))!;
            Assert.Equal(dataDir, report["data_dir"]!.ToString());
            Assert.True(report["data_dir_exists"]!.GetValue<bool>());
            Assert.True(report["control_token_present"]!.GetValue<bool>()); // 服务端刚写过 control.token
            Assert.Equal("ok", report["local_db"]!.ToString());             // 库已建好
            Assert.StartsWith("8x8", report["capture"]!.ToString(), StringComparison.Ordinal); // 真截了一块
            Assert.Matches("^v1-[0-9a-f]{8}$", report["prompt_version"]!.ToString());
            // 绝不该出现密钥字段。
            Assert.False(((JsonObject)report).ContainsKey("api_key"));
        }
        finally
        {
            server.Kill(entireProcessTree: true);
            server.WaitForExit(5000);
        }
    }
}
