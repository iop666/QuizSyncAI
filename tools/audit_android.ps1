# M24（优化轮 · 安卓交付物安全审计）：本地、只读、零第三方依赖。
#
# 为什么自己写，而不用「优化方案」阶段二列的那两个工具（已否决，见 docs/optimization-plan.md）：
#   * flutterguard_cli 需要注册账号拿 API Key，并把 APK **上传到第三方 SaaS** ——
#     违反 AGENTS.md §0.6「不要装需要注册账号的软件」，也与本项目「数据只在本机」的姿态冲突；
#   * flutter_build_guard 的 --fix 会关掉 usesCleartextTraffic（它的 cleartext 规则是 high），
#     直接把局域网搜题打断 —— 而明文 HTTP 是 SPEC §10 明确接受的既定前提。
# 本脚本只用本机已有的 Android SDK 工具：aapt2（读合并后的 manifest）+ apksigner（验签）。
#
# 用法：
#   powershell -File tools\audit_android.ps1                      # 审计 dist\ 下三个 ABI 的 APK
#   powershell -File tools\audit_android.ps1 -ApkPath <某个.apk>   # 只审计一个（开发中用）
param(
  [string]$OutDir = "dist",
  # M47：留空时从 apps\android\pubspec.yaml 读（与打包脚本同一个来源）。
  [string]$Version = "",
  # SDK 位置：显式传参 > 环境变量（ANDROID_SDK_ROOT / ANDROID_HOME）。不写死开发机路径。
  [string]$SdkDir = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }),
  [string]$BuildToolsVersion = "36.0.0",
  [string]$ApkPath = ""
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Join-Path $RepoRoot "apps\android\pubspec.yaml"
  $m = [regex]::Match((Get-Content -Raw -Encoding UTF8 $pubspec), "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)")
  if (-not $m.Success) { Write-Host "FAILED: 读不出 apps\android\pubspec.yaml 的版本号" -ForegroundColor Red; exit 1 }
  $Version = $m.Groups[1].Value
}

# M47：SDK 路径先看参数，再看 ANDROID_HOME / ANDROID_SDK_ROOT，最后才用本机默认位置
# —— 脚本不该只认作者机器的绝对路径。
if ([string]::IsNullOrWhiteSpace($SdkDir) -or -not (Test-Path $SdkDir)) {
  foreach ($envName in @("ANDROID_HOME", "ANDROID_SDK_ROOT")) {
    $candidate = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      $SdkDir = $candidate
      break
    }
  }
}
if (-not (Test-Path $SdkDir)) {
  Write-Host ("FAILED: 找不到 Android SDK（参数、ANDROID_HOME、ANDROID_SDK_ROOT 都没有）：" + $SdkDir) -ForegroundColor Red
  exit 1
}
$aapt2 = Join-Path $SdkDir ("build-tools\" + $BuildToolsVersion + "\aapt2.exe")
$apksigner = Join-Path $SdkDir ("build-tools\" + $BuildToolsVersion + "\apksigner.bat")

# ---- 期望值：与 docs/SPEC.md §10、AndroidManifest.xml 同源。改契约时这里也要改。 ----
$ExpectPackage = "com.quizsync.android"
$ExpectLabel = "AI 双端搜题"
$ExpectMinSdk = "26"
$ExpectTargetSdk = "34"
# 权限白名单：**多一条就报错**。这是本脚本最主要的长期价值 ——
# 某个依赖升级后偷偷加了定位/存储/通讯录权限时，这里会当场变红。
$AllowedPermissions = @(
  "android.permission.INTERNET",
  "android.permission.SYSTEM_ALERT_WINDOW",
  "android.permission.FOREGROUND_SERVICE",
  "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
  "android.permission.POST_NOTIFICATIONS",
  "android.permission.CAMERA",
  "android.permission.ACCESSIBILITY_SERVICE",
  # 下面两条由依赖注入（AndroidX core / 网络状态），不是我们自己声明的
  "android.permission.ACCESS_NETWORK_STATE",
  ($ExpectPackage + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
)
# 交付红线：APK 里绝不允许出现用户数据、密钥材料或签名文件
$ForbiddenEntries = 'userdata|\.jks$|\.keystore$|key\.properties|\.sqlite|secure\.bin|\.pem$'
# Flutter 的 --split-per-abi 会给每个 ABI 加 versionCode 分段（见 app/build.gradle.kts 注释）
$VersionBuckets = @{ "arm64-v8a" = 2000; "armeabi-v7a" = 1000; "x86_64" = 4000 }

$script:failures = 0
$script:checks = 0
function Check {
  param([bool]$Cond, [string]$OkMsg, [string]$FailMsg)
  $script:checks = $script:checks + 1
  if ($Cond) {
    Write-Host ("  [ok]   " + $OkMsg) -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] " + $FailMsg) -ForegroundColor Red
    $script:failures = $script:failures + 1
  }
}

# 读原生命令的 stdout，丢掉 stderr。
# PS 5.1 陷阱（本轮实测踩到，代价是整条审计静默中断）：用 `2>$null` 重定向原生命令的 stderr 时，
# stderr 的每一行都会被包成 ErrorRecord，而在 `$ErrorActionPreference = 'Stop'` 下**第一行就会
# 终止脚本**。apksigner.bat 每次都会往 stderr 写 JVM 警告，于是第一个 APK 审计到签名那一步就断掉、
# 连 FAIL 汇总都没打印（只剩一个 exit 1）。改成「临时 Continue + 2>&1 + 只保留字符串」。
function Get-NativeStdout {
  param([string]$Exe, [string[]]$Arguments)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = & $Exe @Arguments 2>&1
  } finally {
    $ErrorActionPreference = $prev
  }
  return (($raw | Where-Object { $_ -is [string] }) -join "`n")
}

function Audit-Apk {
  param([string]$Apk)
  $name = Split-Path -Leaf $Apk
  Write-Host ""
  Write-Host ("=== " + $name + " ===") -ForegroundColor Cyan
  if (-not (Test-Path $Apk)) {
    Check $false "" ("APK 不存在：" + $Apk)
    return
  }

  $abi = ""
  foreach ($candidate in @("arm64-v8a", "armeabi-v7a", "x86_64")) {
    if ($name -like ("*" + $candidate + "*")) { $abi = $candidate }
  }

  # ---- 1) badging：包身份 / 版本 / 应用名 / SDK 档位 / 权限面 / 调试位 ----
  $badging = Get-NativeStdout $aapt2 @("dump", "badging", $Apk)

  $m = [regex]::Match($badging, "package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'")
  Check $m.Success "读到 package 行" "badging 输出里没有 package 行"
  if ($m.Success) {
    $pkg = $m.Groups[1].Value
    Check ($pkg -eq $ExpectPackage) ("包名 " + $pkg) ("包名应为 " + $ExpectPackage + "，实际 " + $pkg)
    $verName = $m.Groups[3].Value
    Check ($verName -eq $Version) ("versionName " + $verName) ("versionName 应为 " + $Version + "，实际 " + $verName)
    $code = [int]$m.Groups[2].Value
    if ($VersionBuckets.ContainsKey($abi)) {
      $low = $VersionBuckets[$abi]
      $high = $low + 1000
      Check (($code -ge $low) -and ($code -lt $high)) ("versionCode " + $code + " 落在 " + $abi + " 的 " + $low + " 段") ("versionCode " + $code + " 不在 " + $abi + " 期望的 " + $low + "–" + ($high - 1) + " 段")
    }
  }

  $label = [regex]::Match($badging, "application-label:'([^']*)'").Groups[1].Value
  Check ($label -eq $ExpectLabel) ("应用名 " + $label) ("应用名应为 " + $ExpectLabel + "，实际 [" + $label + "]")

  # 字段名是 `minSdkVersion`（大写 S）—— aapt2 输出里没有小写 `sdkVersion` 这个键，
  # 写错会静默拿到空串（本轮实测：minSdk 那一条一直 FAIL 而其余全绿）
  $minSdk = [regex]::Match($badging, "minSdkVersion:'([^']*)'").Groups[1].Value
  $targetSdk = [regex]::Match($badging, "targetSdkVersion:'([^']*)'").Groups[1].Value
  Check ($minSdk -eq $ExpectMinSdk) ("minSdk " + $minSdk) ("minSdk 应为 " + $ExpectMinSdk + "，实际 " + $minSdk)
  Check ($targetSdk -eq $ExpectTargetSdk) ("targetSdk " + $targetSdk) ("targetSdk 应为 " + $ExpectTargetSdk + "，实际 " + $targetSdk)

  Check (-not ($badging -match "application-debuggable")) "不含 application-debuggable（release 构建）" "出现了 application-debuggable：这是可调试构建，不能交付"

  if ($abi -ne "") {
    Check ($badging -match ("native-code: '" + [regex]::Escape($abi) + "'")) ("native-code 含 " + $abi) ("native-code 与文件名不一致（期望 " + $abi + "）")
  }

  $perms = @([regex]::Matches($badging, "uses-permission: name='([^']*)'") | ForEach-Object { $_.Groups[1].Value })
  $extra = @($perms | Where-Object { $AllowedPermissions -notcontains $_ })
  Check ($extra.Count -eq 0) ("权限与白名单一致（共 " + $perms.Count + " 条）") ("出现白名单外的权限：" + ($extra -join ", "))
  foreach ($needed in @("android.permission.INTERNET", "android.permission.CAMERA", "android.permission.SYSTEM_ALERT_WINDOW", "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION")) {
    Check ($perms -contains $needed) ("含必需权限 " + $needed) ("缺少必需权限 " + $needed)
  }

  # ---- 2) xmltree：备份策略与明文开关（M24 的两条安全结论必须真的落在产物上） ----
  $tree = Get-NativeStdout $aapt2 @("dump", "xmltree", "--file", "AndroidManifest.xml", $Apk)
  Check ($tree -match ":allowBackup\(0x[0-9a-f]+\)=false") "allowBackup=false（数据不参与云备份）" "合并后的 manifest 里没有 allowBackup=false"
  Check ($tree -match ":dataExtractionRules\(0x[0-9a-f]+\)=") "声明了 dataExtractionRules（Android 12+ 换机直传也排除）" "缺少 dataExtractionRules：Android 12+ 仍可被 D2D 搬走数据"
  Check ($tree -match ":usesCleartextTraffic\(0x[0-9a-f]+\)=true") "usesCleartextTraffic=true（局域网明文是 SPEC §10 的既定前提）" "usesCleartextTraffic 不是 true：局域网功能会失效"

  # ---- 3) 签名 ----
  if (Test-Path $apksigner) {
    $signer = Get-NativeStdout $apksigner @("verify", "--print-certs", $Apk)
    Check (-not ($signer -match "DOES NOT VERIFY")) "签名校验通过" "签名校验失败（DOES NOT VERIFY）"
    $dn = [regex]::Match($signer, "Signer #1 certificate DN: (.*)").Groups[1].Value.Trim()
    Check ($dn -ne "") ("签名者 " + $dn) "读不到签名者 DN"
  } else {
    Write-Host ("  [skip] 没找到 apksigner：" + $apksigner) -ForegroundColor Yellow
  }

  # ---- 4) 包内文件：交付红线（绝不夹带用户数据 / 密钥 / 数据库） ----
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path $Apk).Path
  $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $bad = @($zip.Entries | Where-Object { $_.FullName -match $ForbiddenEntries } | ForEach-Object { $_.FullName })
    Check ($bad.Count -eq 0) ("包内无 userdata/密钥/数据库（共 " + $zip.Entries.Count + " 项）") ("包内夹带了不该有的文件：" + ($bad -join ", "))
  } finally {
    $zip.Dispose()
  }
}

if (-not (Test-Path $aapt2)) {
  Write-Host ("FAILED: 找不到 aapt2：" + $aapt2 + "（用 -SdkDir / -BuildToolsVersion 指定）") -ForegroundColor Red
  exit 2
}

$targets = @()
if ($ApkPath -ne "") {
  $targets = @($ApkPath)
} else {
  foreach ($abi in @("arm64-v8a", "armeabi-v7a", "x86_64")) {
    $targets += (Join-Path $RepoRoot ($OutDir + "\quizsync-android-" + $abi + "-" + $Version + ".apk"))
  }
}
foreach ($t in $targets) { Audit-Apk $t }

Write-Host ""
if ($script:failures -eq 0) {
  Write-Host ("AUDIT PASS（" + $script:checks + " 项检查全部通过）") -ForegroundColor Green
  exit 0
}
Write-Host ("AUDIT FAIL（" + $script:failures + " / " + $script:checks + " 项未通过）") -ForegroundColor Red
exit 1
