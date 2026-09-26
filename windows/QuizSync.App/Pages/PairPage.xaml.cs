using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using QuizSync.ServerBridge;

namespace QuizSync.App.Pages;

/// <summary>
/// 配对页 —— 原生 2.0 的**第一个真页面**（Phase 6 的界面迁移从这里开始）。
///
/// 走的是已实现的真实链路，不是占位：
/// `HostDiscovery.ProbeAsync()` 探本机服务端 → `HostControl.FindControlToken()` 读控制令牌
/// → `HostControl.PairCodeAsync()` 打 `GET /api/v1/pair/code`（回环 + `X-QS-Control`）。
/// 服务端没起来 / 读不到令牌 / 接口报错，**都如实说明**（连「找过哪些目录」一起给），
/// 绝不在界面上编一个码出来。
/// </summary>
public sealed partial class PairPage : Page
{
    private readonly DispatcherTimer _countdown = new() { Interval = TimeSpan.FromSeconds(1) };
    private long _expiresAtMs;

    public PairPage()
    {
        InitializeComponent();
        _countdown.Tick += (_, _) => UpdateExpiry();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await LoadCodeAsync();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        _countdown.Stop();
    }

    private async void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        RefreshButton.IsEnabled = false;
        try
        {
            await LoadCodeAsync(refresh: true);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }

    private void OnBackClick(object sender, RoutedEventArgs e)
    {
        if (Frame.CanGoBack)
        {
            Frame.GoBack();
        }
        else
        {
            Frame.Navigate(typeof(WelcomePage));
        }
    }

    /// <summary>本机局域网 IPv4 地址（手机要填的那个）。排除回环与未启用的网卡。</summary>
    private static List<string> LanAddresses() =>
        System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces()
            .Where(nic => nic.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                       && nic.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
            .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
            .Select(entry => entry.Address)
            .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork
                           && !System.Net.IPAddress.IsLoopback(address))
            .Select(address => address.ToString())
            .ToList();

    private async Task LoadCodeAsync(bool refresh = false)
    {
        _countdown.Stop();
        StatusText.Text = refresh ? "正在换一个新码…" : "正在查找本机服务端…";
        CodeText.Text = "· · · · · ·";
        ExpiryText.Text = string.Empty;
        HostText.Text = string.Empty;

        try
        {
            var probe = await new HostDiscovery().ProbeAsync().ConfigureAwait(true);
            if (probe is null)
            {
                StatusText.Text = "本机服务端未启动。请先运行 QuizSync.Server.Cli run，再点「换一个码」。";
                return;
            }

            var dataDirectory = HostDataDirectory.Find();
            if (dataDirectory is null)
            {
                StatusText.Text = HostDataDirectory.ExplainMissing();
                return;
            }

            // Find() 已经确认过 control.token 存在，这里再读一次即可。
            var token = HostControl.FindControlToken(dataDirectory);
            if (token is null)
            {
                StatusText.Text = $"在 {dataDirectory} 里读不到控制令牌（control.token）。";
                return;
            }

            var control = new HostControl(probe.BaseUrl, token);
            var result = refresh
                ? await control.RefreshPairCodeAsync().ConfigureAwait(true)
                : await control.PairCodeAsync().ConfigureAwait(true);

            Show(result, probe.BaseUrl);
        }
        catch (Exception error)
        {
            StatusText.Text = $"读取配对码失败：{error.Message}";
        }
    }

    private void Show(JsonObject? payload, string baseUrl)
    {
        var code = payload?["code"]?.ToString();
        if (string.IsNullOrWhiteSpace(code))
        {
            StatusText.Text = "服务端没有返回配对码字段（code）。";
            return;
        }

        // 6 位码分成两组显示，念给对方听的时候不容易串。
        CodeText.Text = code.Length == 6 ? $"{code[..3]} {code[3..]}" : code;

        _expiresAtMs = payload?["expires_at"]?.GetValue<long>() ?? 0;
        var deviceName = payload?["device_name"]?.ToString();
        var port = payload?["port"]?.ToString() ?? "8765";
        // 手机要填的是**局域网**地址 —— 之前界面上根本没显示过它，用户无从下手。
        var lan = LanAddresses();
        HostText.Text = $"本机服务端：{deviceName ?? "未命名"} · 端口 {port}"
                      + (lan.Count == 0
                          ? "\n没找到局域网地址 —— 手机可能连不上，先确认电脑接了 WiFi/网线。"
                          : $"\n手机请填：{string.Join(" 或 ", lan.Select(address => $"{address}:{port}"))}");

        UpdateExpiry();
        if (_expiresAtMs > 0)
        {
            _countdown.Start();
        }

        StatusText.Text = $"配对码已就绪（{baseUrl}）。在手机上输入即可。";
    }

    /// <summary>
    /// 倒计时。协议里配对码有效期 5 分钟，`expires_at` 是服务端给的**绝对**毫秒时间戳，
    /// 所以这里算的是「还剩多久」而不是自己数 300 秒 —— 页面切走再回来也不会算错。
    /// </summary>
    private void UpdateExpiry()
    {
        if (_expiresAtMs <= 0)
        {
            ExpiryText.Text = string.Empty;
            return;
        }

        var remaining = TimeSpan.FromMilliseconds(_expiresAtMs - DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        if (remaining <= TimeSpan.Zero)
        {
            _countdown.Stop();
            ExpiryText.Text = "这个码已过期，点「换一个码」重新生成。";
            return;
        }

        ExpiryText.Text = $"有效期剩余 {(int)remaining.TotalMinutes}:{remaining.Seconds:00}";
    }
}
