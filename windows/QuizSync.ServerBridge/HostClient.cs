using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json.Nodes;

namespace QuizSync.ServerBridge;

/// <summary>
/// 客户端 → 主机的 HTTP 接口（v1 兼容子集，与 Android 侧 `HostApi` 同一批端点）。
///
/// 只做 I/O：拼请求、解析 JSON、把 HTTP 失败变成异常；业务判断不在这里。
/// </summary>
public sealed class HostClient(string baseUrl, HttpClient? client = null)
{
    private readonly HttpClient _client = client ?? new HttpClient();
    private readonly string _base = baseUrl.TrimEnd('/');

    public string? Token { get; private set; }

    public void UseToken(string? token) => Token = token;

    /// <summary>`GET /health`（免鉴权）。</summary>
    public async Task<JsonObject?> HealthAsync(CancellationToken cancellationToken = default) =>
        await SendAsync(HttpMethod.Get, "/health", null, authenticated: false, cancellationToken).ConfigureAwait(false);

    /// <summary>`POST /api/v1/pair`；成功（200/409）时**自动记住 token**。</summary>
    /// <summary>`GET /api/v1/devices`（已配对设备列表；界面「连接设备」用）。</summary>
    public Task<JsonObject?> DevicesAsync(CancellationToken cancellationToken = default) =>
        SendAsync(HttpMethod.Get, "/api/v1/devices", null, authenticated: true, cancellationToken);

    public async Task<JsonObject?> PairAsync(
        string code, string deviceId, string deviceName, string platform = "windows", string appVersion = "2.0.0",
        CancellationToken cancellationToken = default)
    {
        var body = new JsonObject
        {
            ["code"] = code,
            ["device_id"] = deviceId,
            ["device_name"] = deviceName,
            ["platform"] = platform,
            ["app_version"] = appVersion,
        };
        var result = await SendAsync(HttpMethod.Post, "/api/v1/pair", body, authenticated: false, cancellationToken)
            .ConfigureAwait(false);
        if (result?["token"]?.ToString() is { Length: > 0 } token)
        {
            Token = token;
        }

        return result;
    }

    /// <summary>`POST /api/v1/images`（multipart，字段名固定 `file`；内容寻址去重）。</summary>
    public async Task<JsonObject?> UploadImageAsync(
        byte[] jpeg, string filename = "page.jpg", CancellationToken cancellationToken = default)
    {
        using var content = new MultipartFormDataContent();
        var file = new ByteArrayContent(jpeg);
        file.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/jpeg");
        content.Add(file, "file", filename);

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{_base}/api/v1/images") { Content = content };
        if (Token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {Token}");
        }

        return await ReadAsync(request, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>`POST /api/v1/tasks`（恒 202；`status` 是 queued / done）。</summary>
    public async Task<JsonObject?> CreateTaskAsync(
        string taskId, string imageHash, string sourceDevice, CancellationToken cancellationToken = default)
    {
        var body = new JsonObject
        {
            ["task_id"] = taskId,
            ["image_hash"] = imageHash,
            ["source_device"] = sourceDevice,
        };
        return await SendAsync(HttpMethod.Post, "/api/v1/tasks", body, authenticated: true, cancellationToken)
            .ConfigureAwait(false);
    }

    /// <summary>`GET /api/v1/tasks/&lt;id&gt;`。</summary>
    public Task<JsonObject?> GetTaskAsync(string taskId, CancellationToken cancellationToken = default) =>
        SendAsync(HttpMethod.Get, $"/api/v1/tasks/{taskId}", null, authenticated: true, cancellationToken);

    /// <summary>轮询到终态（done / failed）；超时抛异常。</summary>
    public async Task<JsonObject?> AwaitTaskAsync(
        string taskId, TimeSpan timeout, TimeSpan? interval = null, CancellationToken cancellationToken = default)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        var step = interval ?? TimeSpan.FromMilliseconds(100);
        JsonObject? last = null;
        while (DateTimeOffset.UtcNow < deadline)
        {
            last = await GetTaskAsync(taskId, cancellationToken).ConfigureAwait(false);
            var status = last?["status"]?.ToString();
            if (status is "done" or "failed")
            {
                return last;
            }

            await Task.Delay(step, cancellationToken).ConfigureAwait(false);
        }

        throw new TimeoutException($"任务 {taskId} 在 {timeout} 内没到终态，最后状态：{last?.ToJsonString()}");
    }

    /// <summary>`POST /api/v1/sync/ops`（推 op；返回 applied / rejected 计数）。</summary>
    public async Task<JsonObject?> PushOpsAsync(string opsJson, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{_base}/api/v1/sync/ops")
        {
            Content = new StringContent(opsJson, Encoding.UTF8, "application/json"),
        };
        if (Token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {Token}");
        }

        return await ReadAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<JsonObject?> SendAsync(
        HttpMethod method, string path, JsonObject? body, bool authenticated, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, $"{_base}{path}");
        if (body is not null)
        {
            request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        }

        if (authenticated && Token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {Token}");
        }

        return await ReadAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<JsonObject?> ReadAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await _client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var text = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        JsonObject? json = null;
        try
        {
            json = JsonNode.Parse(text) as JsonObject;
        }
        catch (System.Text.Json.JsonException)
        {
            json = null;
        }

        if (!response.IsSuccessStatusCode)
        {
            var code = json?["code"]?.ToString() ?? ((int)response.StatusCode).ToString();
            var message = json?["message"]?.ToString() ?? text;
            throw new HostException((int)response.StatusCode, code, message);
        }

        return json;
    }
}

/// <summary>主机返回的错误（协议里的 `{code,message,retry_after_seconds?}`）。</summary>
public sealed class HostException(int statusCode, string code, string message) : Exception($"{code} ({statusCode}): {message}")
{
    public int StatusCode { get; } = statusCode;

    public string Code { get; } = code;
}

/// <summary>控制面（回环 + `X-QS-Control`）：读配对码、刷新配对码。</summary>
public sealed class HostControl(string baseUrl, string controlToken, HttpClient? client = null)
{
    private readonly HttpClient _client = client ?? new HttpClient();

    public static string? FindControlToken(string dataDirectory)
    {
        var path = Path.Combine(dataDirectory, "control.token");
        return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
    }

    public Task<JsonObject?> PairCodeAsync(CancellationToken cancellationToken = default) =>
        CallAsync("/api/v1/pair/code", cancellationToken);

    public Task<JsonObject?> RefreshPairCodeAsync(CancellationToken cancellationToken = default) =>
        CallAsync("/api/v1/pair/code/refresh", cancellationToken);

    private async Task<JsonObject?> CallAsync(string path, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl.TrimEnd('/')}{path}");
        request.Headers.TryAddWithoutValidation("X-QS-Control", controlToken);
        using var response = await _client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var text = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new HostException((int)response.StatusCode, "control_denied", text);
        }

        return JsonNode.Parse(text) as JsonObject;
    }
}
