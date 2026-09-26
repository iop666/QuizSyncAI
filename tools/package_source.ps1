# Package the deliverable source snapshot into dist\quizsync-source-<version>.zip
#
# 为什么有这个脚本（M46 第 6/7 条）：
#   * 用户要求「源码包要带 19MB 的 MiSans 字体：不带就没人能直接构建
#     （pubspec 声明了它）」—— 字体（apps/desktop/assets/fonts/MiSans-VF.ttf，
#     20,000,736 字节）必须**真的进 zip**，否则拿到源码的人 pub get 之后构建
#     会因为缺字体资源失败。随包分发符合小米 MiSans FAQ（可嵌入软件随软件分发，
#     但不得单独再分发字体文件本身）。
#   * 用户要求「排除所有测试」—— 源码包里**不带任何测试**：任何一段路径叫
#     test / integration_test / androidTest / test_driver 的目录，以及 *_test.dart /
#     *_test.kt 文件一律剔除（README 里也写着「本源码包不含测试目录」）。
#     没有 test 目录时 `tools/build_all.ps1` 会自动跳过测试步骤，构建照常。
#   * 用户要求「除去正式版软件中一些构建中的介绍等信息」—— 源码包里**不带**
#     内部构建过程记录：AGENTS.md、docs/DECISIONS.md、milestones.md、progress.md、
#     DEV.md、optimization-plan.md、manual-test-android.md、agent-kickoff-prompt.md。
#     只保留真正对使用者有用的工程文档：SPEC / protocol / data-model / ai-contract。
#
# 用法：
#   powershell -File tools\package_source.ps1                 # 版本取 apps\desktop\pubspec.yaml
#   powershell -File tools\package_source.ps1 -Version 1.1.0
#
# 产出：dist\quizsync-source-<version>.zip（zip 内**没有**外层目录，
#       `.gitignore` / `LICENSE` / `README.md` 就在根上，解压即可 pub get）。
param(
  [string]$Version = "",
  [string]$OutDir = "dist"
)
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Join-Path $RepoRoot "apps\desktop\pubspec.yaml"
  $m = [regex]::Match((Get-Content -Raw -Encoding UTF8 $pubspec), "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)")
  if (-not $m.Success) { Write-Host "FAILED: 读不出 apps\desktop\pubspec.yaml 的版本号" -ForegroundColor Red; exit 1 }
  $Version = $m.Groups[1].Value
}

$out = Join-Path $RepoRoot $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null
$zipPath = Join-Path $out ("quizsync-source-" + $Version + ".zip")

# ---- 排除规则：路径片段（用 / 分隔，大小写不敏感） ----
$excludeSegments = @(
  ".git/", ".dart_tool/", ".idea/", ".vscode/", ".gradle/",
  "build/", "dist/", "userdata/", "ephemeral/"
)
# ---- 排除规则：**只在仓库根**下的目录（同名子目录要保留！） ----
# `fonts\` 是 200MB 的字体母版；而 `apps\desktop\assets\fonts\` 是随包字体，
# 必须**保留**（M46 第 6 条）。所以这两条按「以该前缀开头」判断，不能按包含判断。
$excludeRootDirs = @("fonts/", "keystore/", "dist/")
# ---- 排除规则：具体相对路径（内部构建过程记录，M46 第 7 条） ----
$excludeFiles = @(
  "AGENTS.md",
  "docs/DECISIONS.md",
  "docs/DEV.md",
  "docs/milestones.md",
  "docs/progress.md",
  "docs/optimization-plan.md",
  "docs/manual-test-android.md",
  "docs/agent-kickoff-prompt.md",
  "apps/android/android/local.properties",
  "apps/android/android/key.properties",
  # Flutter 工具生成的痕迹（它们本来就在 .gitignore 里，公开源码里也不该出现）：
  "apps/android/.flutter-plugins-dependencies",
  "apps/desktop/.flutter-plugins-dependencies",
  "apps/android/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
  # 纯 Dart 包的 lock 文件按惯例不入库（应用层的 lock 仍然保留）：
  "packages/quizsync_core/pubspec.lock",
  "packages/quizsync_ui/pubspec.lock"
)
# ---- 排除规则：**所有测试**（按路径段精确比较，不能按包含判断 —— "contest/" 里也含 "test/"） ----
$excludeTestSegments = @("test", "integration_test", "androidtest", "test_driver")
# ---- 排除规则：文件名模式 ----
# `.env*` 是防护网缺口：现在仓库里没有 .env，但哪天有人建了，收集用的是
# `Get-ChildItem -Force`，它会被原样打进公开源码包（M47）。
$excludePatterns = @("*.log", "*.zip", "*.jks", "*.keystore", "*.iml", "Thumbs.db", ".DS_Store", ".env*")

# 只从这些顶层目录/文件收集（其余一律不进包）。
$includeRoots = @(
  ".gitignore", "LICENSE", "README.md",
  "apps", "packages", "tools", "server", "icon", "docs"
)

function Test-Excluded([string]$rel) {
  $lower = $rel.Replace("\", "/").ToLowerInvariant()
  foreach ($seg in $excludeSegments) {
    if ($lower.Contains($seg.ToLowerInvariant())) { return $true }
  }
  foreach ($dir in $excludeRootDirs) {
    if ($lower.StartsWith($dir.ToLowerInvariant())) { return $true }
  }
  if ($excludeFiles -contains $rel.Replace("\", "/")) { return $true }
  $segs = $lower.Split("/")
  foreach ($t in $excludeTestSegments) {
    if ($segs -contains $t) { return $true }
  }
  if ($lower.EndsWith("_test.dart") -or $lower.EndsWith("_test.kt")) { return $true }
  $name = Split-Path $rel -Leaf
  foreach ($pat in $excludePatterns) {
    if ($name -like $pat) { return $true }
  }
  return $false
}

$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($root in $includeRoots) {
  $full = Join-Path $RepoRoot $root
  if (-not (Test-Path $full)) {
    Write-Host ("WARN: 缺少 " + $root + "，跳过") -ForegroundColor Yellow
    continue
  }
  $item = Get-Item -Force $full
  if ($item.PSIsContainer) {
    # Junction / 符号链接一律不递归（AGENTS.md 里记过 Remove-Item 跟着链接删目标的坑）。
    foreach ($f in (Get-ChildItem -Recurse -File -Force $full)) {
      $rel = $f.FullName.Substring($RepoRoot.Length + 1)
      if (-not (Test-Excluded $rel)) { $files.Add($f) }
    }
  } else {
    $files.Add($item)
  }
}

if ($files.Count -eq 0) {
  Write-Host "FAILED: 没有收集到任何文件" -ForegroundColor Red
  exit 1
}

# 交付红线：任何用户数据 / 密钥都不许进包。
$leak = @($files | Where-Object {
    $_.Name -match '(?i)\.(sqlite|db|sqlite-wal|sqlite-shm|jks|keystore)$' -or
    $_.Name -like '.env*' -or
    $_.FullName -match '(?i)\\userdata\\'
  })
if ($leak.Count -gt 0) {
  Write-Host ("FAILED: 源码包里混进了用户数据/密钥：" + (($leak | ForEach-Object { $_.Name }) -join ", ")) -ForegroundColor Red
  exit 1
}

# ---- 写 zip（条目名用正斜杠；Compress-Archive 会写反斜杠，跨平台解压不友好） ----
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipPath) {
  for ($i = 0; $i -lt 10; $i++) {
    try { Remove-Item $zipPath -Force; break } catch { Start-Sleep -Seconds 2 }
  }
  if (Test-Path $zipPath) {
    Write-Host ("FAILED: 旧 zip 删不掉（很可能被解压工具占用）：" + $zipPath) -ForegroundColor Red
    exit 1
  }
}

$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($RepoRoot.Length + 1).Replace("\", "/")
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $archive, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
  }
} finally {
  $archive.Dispose()
}

# ---- 复核：字体必须在、内部记录必须不在、产物目录必须不在 ----
$verify = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $names = @($verify.Entries | ForEach-Object { $_.FullName })
  $font = $verify.Entries | Where-Object { $_.FullName -eq "apps/desktop/assets/fonts/MiSans-VF.ttf" }
  if ($null -eq $font) {
    Write-Host "FAILED: 源码包里没有 MiSans-VF.ttf（没有它别人 pub get 后构建不出来）" -ForegroundColor Red
    exit 1
  }
  if ($font.Length -lt 19000000) {
    Write-Host ("FAILED: MiSans-VF.ttf 只有 " + $font.Length + " 字节，疑似被截断") -ForegroundColor Red
    exit 1
  }
  $forbidden = @($names | Where-Object { $excludeFiles -contains $_ })
  if ($forbidden.Count -gt 0) {
    Write-Host ("FAILED: 源码包里仍有构建过程记录：" + ($forbidden -join ", ")) -ForegroundColor Red
    exit 1
  }
  $junk = @($names | Where-Object { $_ -match '(?i)(^|/)(build|userdata|\.dart_tool|\.git)/' -or $_ -match '(?i)\.(zip|log|jks|keystore)$' })
  if ($junk.Count -gt 0) {
    Write-Host ("FAILED: 源码包里混进了构建产物/日志：" + (($junk | Select-Object -First 5) -join ", ")) -ForegroundColor Red
    exit 1
  }
  $tests = @($names | Where-Object {
      $_ -match '(?i)(^|/)(test|integration_test|androidTest|test_driver)/' -or
      $_ -match '(?i)_test\.(dart|kt)$' })
  if ($tests.Count -gt 0) {
    Write-Host ("FAILED: 源码包里仍有测试：" + (($tests | Select-Object -First 5) -join ", ")) -ForegroundColor Red
    exit 1
  }
  $hasServer = @($names | Where-Object { $_ -like "server/*" }).Count -gt 0
  $size = (Get-Item $zipPath).Length / 1MB
  Write-Host ("source zip: " + $zipPath) -ForegroundColor Green
  Write-Host ("  条目 " + $names.Count + " 个 / " + [math]::Round($size, 1) + " MB（含 MiSans " + [math]::Round($font.Length / 1MB, 1) + " MB）")
  Write-Host ("  工程文档：SPEC / protocol / data-model / ai-contract；server 源码：" + $(if ($hasServer) { "已包含" } else { "未包含" }))
  Write-Host "  （测试目录与 *_test.dart 已全部剔除；内部构建记录 AGENTS.md / DECISIONS / milestones / progress / DEV 等一并剔除）"
} finally {
  $verify.Dispose()
}
exit 0
