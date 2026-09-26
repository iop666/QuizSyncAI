using System.Net;
using System.Net.Http;

namespace QuizSync.ServerBridge;

/// <summary>一次探测的结果。</summary>
public sealed record HostProbe(string BaseUrl, string ProtocolVersion, string ServerDeviceId, int Port);

/// <summary>
/// 找主机：在 8765 起向上探测（与主机侧的端口探测范围一致，见协议 `HTTP_HOST_PORT=8765`）。
///
/// 纪律：**只认 /health 真的回了预期 JSON**，端口开着但回的别的东西（比如别的程序占了）
/// 不算主机 —— 否则会把请求打给陌生服务。
/// </summary>
public sealed class HostDiscovery(HttpClient? client = null)
{
    public const int BasePort = 8765;
    public const int PortSpan = 6;

    private readonly HttpClient _client = client ?? new HttpClient { Timeout = TimeSpan.FromMilliseconds(800) };

    public static IEnumerable<int> CandidatePorts() => Enumerable.Range(BasePort, PortSpan);

    /// <summary>按端口顺序探测，返回第一个像主机的；都没有则 null。</summary>
    public async Task<HostProbe?> ProbeAsync(string host = "127.0.0.1", CancellationToken cancellationToken = default)
    {
        foreach (var port in CandidatePorts())
        {
            var probe = await ProbePortAsync(host, port, cancellationToken).ConfigureAwait(false);
            if (probe is not null)
            {
                return probe;
            }
        }

        return null;
    }

    public async Task<HostProbe?> ProbePortAsync(string host, int port, CancellationToken cancellationToken = default)
    {
        var baseUrl = $"http://{host}:{port}";
        try
        {
            using var response = await _client.GetAsync($"{baseUrl}/health", cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var text = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            var json = System.Text.Json.Nodes.JsonNode.Parse(text) as System.Text.Json.Nodes.JsonObject;
            // 必须是我们认识的形状：`status` 说明它是本协议的主机。
            if (json?["status"]?.ToString() != "ok")
            {
                return null;
            }

            return new HostProbe(
                baseUrl,
                json["protocol_version"]?.ToString() ?? string.Empty,
                json["server_device_id"]?.ToString() ?? string.Empty,
                port);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            return null;
        }
    }
}

/// <summary>
/// 单实例：同一个数据目录只允许一个进程持有（跨进程可见的命名互斥体）。
///
/// 判据用 `createdNew`（**是不是我创建的**）而不是 `WaitOne`：
/// - 命名互斥体对同一线程可重入，用 `WaitOne(0)` 在自己进程里建第二个实例会误判成「拿到」；
/// - `ReleaseMutex` 必须由**持有它的那条线程**调用，而 await 之后可能换了线程 → 会抛
///   `ApplicationException: ... unsynchronized block`。句柄随进程退出释放即可，不用手动 Release。
/// </summary>
public sealed class SingleInstance : IDisposable
{
    private readonly Mutex _mutex;

    public SingleInstance(string name)
    {
        _mutex = new Mutex(initiallyOwned: true, name: name, createdNew: out var createdNew);
        IsOwner = createdNew;
    }

    public bool IsOwner { get; }

    public void Dispose() => _mutex.Dispose();
}
