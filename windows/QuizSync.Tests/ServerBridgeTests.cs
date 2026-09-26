using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using QuizSync.Data;
using QuizSync.ServerBridge;
using Xunit;

namespace QuizSync.Tests;

/// <summary>假 HTTP 处理器：不出网。</summary>
internal sealed class StubHandler(Func<HttpRequestMessage, (HttpStatusCode Status, string Body)> script) : HttpMessageHandler
{
    public List<string> Paths { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Paths.Add(request.RequestUri!.AbsolutePath);
        var (status, body) = script(request);
        return Task.FromResult(new HttpResponseMessage(status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        });
    }
}

public sealed class HostDiscoveryTests
{
    [Fact]
    public async Task Health_shaped_like_a_host_is_accepted()
    {
        var handler = new StubHandler(_ => (HttpStatusCode.OK,
            """{"status":"ok","protocol_version":"1","server_device_id":"dev-1"}"""));
        var discovery = new HostDiscovery(new HttpClient(handler));

        var probe = await discovery.ProbeAsync();

        Assert.NotNull(probe);
        Assert.Equal("dev-1", probe!.ServerDeviceId);
        Assert.Equal(HostDiscovery.BasePort, probe.Port);
        Assert.Single(handler.Paths); // 第一个端口就命中，不再往后面试
    }

    [Fact]
    public async Task Foreign_service_on_the_port_is_not_mistaken_for_a_host()
    {
        // 端口开着、也回 200，但不是我们的形状 → 必须继续/放弃，绝不能把请求打给陌生服务。
        var handler = new StubHandler(_ => (HttpStatusCode.OK, """{"hello":"world"}"""));
        var discovery = new HostDiscovery(new HttpClient(handler));

        var probe = await discovery.ProbeAsync();

        Assert.Null(probe);
        Assert.Equal(HostDiscovery.PortSpan, handler.Paths.Count); // 6 个端口都试过
    }

    [Fact]
    public async Task Later_port_is_found_when_earlier_ones_fail()
    {
        var handler = new StubHandler(request =>
            request.RequestUri!.Port == HostDiscovery.BasePort + 2
                ? (HttpStatusCode.OK, """{"status":"ok","protocol_version":"1","server_device_id":"dev-3"}""")
                : (HttpStatusCode.ServiceUnavailable, "{}"));
        var discovery = new HostDiscovery(new HttpClient(handler));

        var probe = await discovery.ProbeAsync();

        Assert.Equal(HostDiscovery.BasePort + 2, probe!.Port);
    }

    [Fact]
    public async Task Single_instance_lets_only_one_owner_in()
    {
        var name = $"QuizSync.Test.{Guid.NewGuid():N}";
        using var first = new SingleInstance(name);
        Assert.True(first.IsOwner);

        // 命名互斥体对**同一个线程**是可重入的（WaitOne 会再次成功），所以第二个实例
        // 必须换一条线程建 —— 真实场景里本来就是两个进程。
        var secondOwned = await Task.Run(() =>
        {
            using var second = new SingleInstance(name);
            return second.IsOwner;
        });

        Assert.False(secondOwned);
    }

    [Fact]
    public void Control_token_is_read_from_the_data_directory()
    {
        var dir = Directory.CreateTempSubdirectory("qs-bridge-").FullName;
        try
        {
            Assert.Null(HostControl.FindControlToken(dir));
            File.WriteAllText(Path.Combine(dir, "control.token"), "abc123\n");
            Assert.Equal("abc123", HostControl.FindControlToken(dir));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}

/// <summary>
/// **跨实现端到端**：C# 客户端（ServerBridge）→ 真实的 C# Server（Phase 2 的产物）。
/// 与 Android 侧那条 Kotlin E2E 同一套流程，验证 Windows 内核也能和主机对话。
/// </summary>
public sealed class ServerBridgeEndToEndTests
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
            ?? throw new FileNotFoundException(
                "找不到 C# 服务端产物。先执行：dotnet publish QuizSyncServer/src/QuizSync.Server.Cli -c Release -o src/QuizSync.Server.Cli/bin/Release/publish\n" +
                "或用环境变量 QS_SERVER_DLL 指定 dll。试过：" + string.Join(", ", candidates));
    }

    private static string Dotnet()
    {
        var configured = Environment.GetEnvironmentVariable("QS_DOTNET");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return configured;
        }

        // PATH 里没有 dotnet 时给一句能照做的提示（本机就是这种情况：SDK 装在用户目录、没进 PATH）。
        try
        {
            using var probe = Process.Start(new ProcessStartInfo("dotnet") { ArgumentList = { "--version" }, RedirectStandardOutput = true })!;
            probe.WaitForExit(5000);
            return "dotnet";
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            throw new InvalidOperationException(
                "PATH 里找不到 dotnet。请设置环境变量 QS_DOTNET 指向 dotnet 可执行文件后重跑。", error);
        }
    }

    private static int FreePort()
    {
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    [Fact]
    public async Task Windows_bridge_pairs_uploads_and_gets_a_result_from_the_real_server()
    {
        var dataDir = Directory.CreateTempSubdirectory("qs-bridge-e2e-").FullName;
        var port = FreePort();
        var started = Process.Start(new ProcessStartInfo(Dotnet())
        {
            ArgumentList = { ServerDll(), "run", "--port", port.ToString(), "--data", dataDir },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;

        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var discovery = new HostDiscovery(http);
            var client = new HostClient($"http://127.0.0.1:{port}", http);

            // 1) 探活（最多 20 秒）。
            HostProbe? probe = null;
            var deadline = DateTimeOffset.UtcNow.AddSeconds(20);
            while (DateTimeOffset.UtcNow < deadline && probe is null)
            {
                probe = await discovery.ProbePortAsync("127.0.0.1", port);
                if (probe is null)
                {
                    await Task.Delay(250);
                }
            }

            Assert.NotNull(probe);
            // 主机现在同时提供 v1 兼容层与 v2：`/health` 报的版本随实现走，只要求是个合法数字。
            Assert.True(int.TryParse(probe!.ProtocolVersion, out var version) && version >= 1,
                $"协议版本异常：{probe.ProtocolVersion}");

            // 2) 读配对码（本机控制面）。
            var controlToken = HostControl.FindControlToken(dataDir);
            Assert.NotNull(controlToken);
            Assert.Equal(64, controlToken!.Length);
            var control = new HostControl($"http://127.0.0.1:{port}", controlToken, http);
            var pairCode = (await control.PairCodeAsync())!["code"]!.ToString();
            Assert.Equal(6, pairCode.Length);

            // 3) 配对 → 自动记住 token。
            var pair = await client.PairAsync(pairCode, "windows-bridge-1", "Windows 桥测试机");
            Assert.NotNull(pair);
            Assert.False(string.IsNullOrEmpty(client.Token));

            // 4) 给主机播种合集（任务必须落在合集里）。
            using (var database = QuizDatabase.OpenExisting(Path.Combine(dataDir, "quizsync.db")))
            {
                database.Execute(
                    "INSERT INTO collections (collection_id, name, created_at, updated_at, updated_by, lamport) " +
                    "VALUES ('c-bridge', '桥测试合集', 1700000000000, 1700000000000, 'server-device-1', 0)");
                database.Execute("INSERT INTO settings (key, value) VALUES ('active_collection_id', 'c-bridge')");
            }

            // 5) 上传（含内容寻址去重）。
            byte[] jpeg = [0xFF, 0xD8, 0x01, 0xFF, 0xD9];
            var upload = await client.UploadImageAsync(jpeg);
            var hash = upload!["image_hash"]!.ToString();
            Assert.Equal(64, hash.Length);
            Assert.False(upload["existed"]!.GetValue<bool>());
            Assert.True((await client.UploadImageAsync(jpeg))!["existed"]!.GetValue<bool>());

            // 6) 建任务 → 202、提交那刻 0 题 → 轮询到 done。
            var task = await client.CreateTaskAsync("t-bridge-1", hash, "windows-bridge-1");
            Assert.Equal("queued", task!["status"]!.ToString());
            Assert.Equal(0, task["question_count"]!.GetValue<int>());

            var done = await client.AwaitTaskAsync("t-bridge-1", TimeSpan.FromSeconds(30));
            Assert.Equal("done", done!["status"]!.ToString());
            Assert.Equal(1, done["session"]!["question_count"]!.GetValue<int>());

            // 7) 幂等复提。
            var repeat = await client.CreateTaskAsync("t-bridge-1", hash, "windows-bridge-1");
            Assert.Equal("done", repeat!["status"]!.ToString());
            Assert.True(repeat["cached"]!.GetValue<bool>());

            // 8) 冒充别人推 op → 必须被拒。
            var push = await client.PushOpsAsync(
                """{"ops":[{"op_id":"op-bridge-1","device_id":"someone-else","lamport":1,"entity":"question","entity_id":"q-bridge-1","op_type":"upsert","fields_json":{}}]}""");
            Assert.Equal(0, push!["applied"]!.GetValue<int>());
            Assert.Equal(1, push["rejected"]!.GetValue<int>());

            // 9) 未带 token 的客户端会被拒（负向）。
            var anonymous = new HostClient($"http://127.0.0.1:{port}", http);
            var error = await Assert.ThrowsAsync<HostException>(() => anonymous.GetTaskAsync("t-bridge-1"));
            Assert.Equal(401, error.StatusCode);
        }
        finally
        {
            started.Kill(entireProcessTree: true);
            started.WaitForExit(5000);
        }
    }
}
