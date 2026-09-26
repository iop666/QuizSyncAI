using System.IO;
using System.Text.Json.Nodes;
using QuizSync.Data;
using QuizSync.ServerBridge;

namespace QuizSync.App;

/// <summary>
/// 把本地生成的 op 推到主机。
///
/// **为什么需要它**（第十一轮发现）：电脑识别完只写自己的本地库、从不 push，
/// 所以手机端永远拉不到东西 —— 我验 Android 拉取时只能用脚本给服务端「播种」。
/// 补上这一段，双端才算真的闭环。
///
/// 自己与主机配对拿设备令牌（用控制面读配对码 → `POST /api/v1/pair`），
/// 令牌与推送水位存在 `<app>/userdata/` 下。
/// **注意**：令牌是密钥，这里先落普通文件（与控制令牌同一处理），
/// 迁到 DPAPI 单独一轮做（已记在 DECISIONS）。
/// </summary>
public static class SyncUploader
{
    /// <summary>
    /// 本应用的设备标识。**不能等于主机自己的 device_id**（主机是 `windows-local`）。
    ///
    /// 第十二轮实测撞到：原来这里写的就是 `windows-local`，于是服务端认为这些 op
    /// 「声称由主机自己产生」，按防冒充规则**静默跳过**（`applied`/`rejected` 都不计）——
    /// 界面显示「已推送 6 条改动（主机接受 0、拒绝 0）」，服务端一条都没落。
    /// 规则本身写得很清楚（`SyncService.cs` 第 17 行），是我把 id 取重了。
    /// </summary>
    public const string DeviceId = "windows-desktop";
    private const string TokenFile = "device.token";
    private const string WatermarkFile = "sync.watermark";

    /// <summary>推送尚未上传的 op；返回一句给用户看的结果。</summary>
    public static async Task<string> PushPendingAsync(QuizDatabase database, string baseUrl, string controlToken)
    {
        var directory = AppDataDirectory.Ensure();
        var client = new HostClient(baseUrl);

        var tokenPath = Path.Combine(directory, TokenFile);
        var token = File.Exists(tokenPath) ? SecretStore.Unprotect(File.ReadAllText(tokenPath).Trim()) : null;
        if (string.IsNullOrEmpty(token))
        {
            // 自己跟主机配对：配对码本来就是我们（控制面）读出来显示给用户的。
            var control = new HostControl(baseUrl, controlToken);
            var pairCode = await control.PairCodeAsync().ConfigureAwait(false);
            var code = pairCode?["code"]?.ToString();
            if (string.IsNullOrWhiteSpace(code))
            {
                throw new InvalidOperationException("读不到配对码，无法取得设备令牌");
            }

            string? issuedToken = null;
            try
            {
                var issued = await client.PairAsync(code!, DeviceId, Environment.MachineName).ConfigureAwait(false);
                issuedToken = issued?["token"]?.ToString();
            }
            catch (HostException error) when (error.StatusCode == 409)
            {
                // **409 = 重复配对，在协议里算成功**（服务端照样发新 token，见 spec/04-http-api.md；
                // Android 侧一直按这个语义处理，Windows 侧原来漏了 —— 第二十三轮实测撞到）。
                // `HostClient` 对非 2xx 一律抛异常，而异常的 Message 就是响应体，所以从这里取 token。
                issuedToken = System.Text.Json.Nodes.JsonNode.Parse(error.Message)?["token"]?.ToString();
            }

            token = issuedToken;
            if (string.IsNullOrWhiteSpace(token))
            {
                throw new InvalidOperationException("主机没有返回访问令牌");
            }

            // **加密落盘**（与 AI Key 同一套 `SecretStore`）：设备令牌原来也是明文。
            File.WriteAllText(tokenPath, SecretStore.Protect(token));
        }

        client.UseToken(token);

        var watermarkPath = Path.Combine(directory, WatermarkFile);
        var since = File.Exists(watermarkPath)
            && long.TryParse(File.ReadAllText(watermarkPath).Trim(), out var parsed) ? parsed : 0L;

        var store = new LocalStore(database, DeviceId);
        var ops = store.LocalOpsSince(since);
        if (ops.Count == 0)
        {
            return "没有待推送的改动";
        }

        var body = new JsonObject { ["ops"] = new JsonArray([.. ops.Select(op => (JsonNode)op.ToJson())]) };
        var result = await client.PushOpsAsync(body.ToJsonString()).ConfigureAwait(false);
        var applied = result?["applied"]?.GetValue<int>() ?? 0;
        var rejected = result?["rejected"]?.GetValue<int>() ?? 0;

        // 只有主机**收下了**才推进水位：被拒的 op 下次还会重推（否则就永久丢了）。
        if (rejected == 0)
        {
            File.WriteAllText(watermarkPath, ops.Max(op => op.Lamport).ToString(System.Globalization.CultureInfo.InvariantCulture));
        }

        return $"已推送 {ops.Count} 条改动（主机接受 {applied}、拒绝 {rejected}）";
    }
}
