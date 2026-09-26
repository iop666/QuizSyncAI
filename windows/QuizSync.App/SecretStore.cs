using System.Security.Cryptography;
using System.Text;

namespace QuizSync.App;

/// <summary>
/// 本机敏感值（AI Key、设备令牌）的**加密落盘**。
///
/// 之前这两样都是**明文**写在 `userdata/ai.json` 与 `device.token` 里 ——
/// 设置页上我还专门写明了「目前明文」。这一版用 **DPAPI**（`ProtectedData`，
/// `CurrentUser` 作用域）加密：只有**同一台机器上的同一个 Windows 用户**能解开，
/// 把文件拷到别的机器 / 别的账户都打不开。
///
/// **边界要说清楚**（不夸大）：DPAPI 挡的是「**文件被拷走**」这一类风险，
/// 它**挡不住**同一用户下运行的程序 —— 解密本来就要以该用户身份进行。
/// 所以它不是保险箱，只是把「明文躺在磁盘上」变成「密文躺在磁盘上」。
///
/// 格式：`dpapi:` 前缀 + Base64 密文。读到**没有前缀**的值时按明文处理（下次保存时升级为密文），
/// 这样老配置文件不会因为这次改动而失效，也不会静默丢掉用户已经填好的 Key。
/// </summary>
public static class SecretStore
{
    private const string Prefix = "dpapi:";

    /// <summary>加密。加密不可用时**返回原文** —— 宁可不加密，也不能让用户配置不了。</summary>
    public static string Protect(string plain)
    {
        if (string.IsNullOrEmpty(plain) || plain.StartsWith(Prefix, StringComparison.Ordinal))
        {
            return plain;
        }

        try
        {
            var encrypted = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(plain), optionalEntropy: null, DataProtectionScope.CurrentUser);
            return Prefix + Convert.ToBase64String(encrypted);
        }
        catch (Exception error) when (error is CryptographicException or PlatformNotSupportedException)
        {
            return plain;
        }
    }

    /// <summary>解密。老配置里的明文原样返回（下次保存时会被升级成密文）。</summary>
    public static string Unprotect(string stored)
    {
        if (string.IsNullOrEmpty(stored) || !stored.StartsWith(Prefix, StringComparison.Ordinal))
        {
            return stored;
        }

        try
        {
            var decrypted = ProtectedData.Unprotect(
                Convert.FromBase64String(stored[Prefix.Length..]), optionalEntropy: null,
                DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(decrypted);
        }
        catch (Exception error) when (error is CryptographicException or FormatException)
        {
            // 换个 Windows 用户或换台机器就解不开 —— 这不是崩溃的理由：
            // 当作「没有配置」返回，界面会提示用户重新填一次。
            return string.Empty;
        }
    }

    /// <summary>这个值是不是已经加密过了（设置页用它来如实告诉用户当前状态）。</summary>
    public static bool IsProtected(string stored) =>
        !string.IsNullOrEmpty(stored) && stored.StartsWith(Prefix, StringComparison.Ordinal);
}
