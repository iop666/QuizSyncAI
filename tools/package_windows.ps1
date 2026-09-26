# Package portable zip + Inno Setup installer when ISCC.exe is available.
param(
  # M47：默认不写死版本 —— 留空时从 apps\desktop\pubspec.yaml 读（唯一来源）。
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
# M47：flutter 先按 PATH 找，找不到再用本机安装位置。
$Flutter = $null
$cmd = Get-Command flutter.bat -ErrorAction SilentlyContinue
if ($cmd) { $Flutter = $cmd.Source }
if (-not $Flutter) {
  # 环境变量兜底（不写死开发机路径）。
  if ($env:FLUTTER_BAT -and (Test-Path $env:FLUTTER_BAT)) { $Flutter = $env:FLUTTER_BAT }
}
if (-not $Flutter) {
  Write-Host "FAILED: 找不到 flutter（PATH 里没有）" -ForegroundColor Red
  exit 1
}

$releaseDir = Join-Path $RepoRoot "apps\desktop\build\windows\x64\runner\Release"
$exe = Join-Path $releaseDir "quizsync_desktop.exe"

# M26（用户拍板）：找到随包的 VC++ 运行库目录。
# exe 是**动态链接** MSVC 运行库的（导入表里就有 VCRUNTIME140.dll / MSVCP140.dll），
# 而 Flutter 的 Release 目录默认**不含**它们 —— 没装「VC++ 2015–2022 x64 运行库」的电脑
# 双击就是缺 DLL 起不来（M24 实测：当时的便携版 zip 54 个条目里一个都没有）。
# 这里定位 VS 自带的可再发行 CRT 目录（`...\VC\Redist\MSVC\<ver>\x64\Microsoft.VC*.CRT`）。
function Find-VcRuntimeDir {
  $candidates = @()
  foreach ($root in @("C:\Program Files (x86)\Microsoft Visual Studio", "C:\Program Files\Microsoft Visual Studio")) {
    if (-not (Test-Path $root)) { continue }
    $candidates += @(Get-ChildItem -Path $root -Recurse -Directory -Filter "Microsoft.VC*.CRT" -ErrorAction SilentlyContinue |
        Where-Object {
          # 必须排除 `\onecore\`：那是给 OneCore/UWP 目标的**精简版** CRT，与桌面版同名但
          # **不同文件**（实测 msvcp140.dll 631808 vs 643512 字节、哈希不同、vcruntime140.dll
          # 168960 vs 178616）。第一版就是漏了这条过滤而选中了 onecore，拿它跑 Win32 桌面应用是错的。
          $_.FullName -match '\\Redist\\' -and $_.FullName -match '\\x64\\' -and $_.FullName -notmatch '\\onecore\\'
        })
  }
  if ($candidates.Count -eq 0) { return $null }
  $best = $null
  $bestVer = $null
  foreach ($c in $candidates) {
    $m = [regex]::Match($c.FullName, '\\MSVC\\([0-9.]+)\\')
    if (-not $m.Success) { continue }
    $v = $null
    try { $v = [version]$m.Groups[1].Value } catch { continue }
    if (($null -eq $bestVer) -or ($v -gt $bestVer)) { $bestVer = $v; $best = $c }
  }
  if ($null -eq $best) { return $candidates[0].FullName }
  return $best.FullName
}

if (-not (Test-Path $exe)) {
  Write-Host "Building Windows release first..."
  Push-Location (Join-Path $RepoRoot "apps\desktop")
  # --no-tree-shake-icons：见 build_all.ps1 里的说明（图标字体必须完整）。
  & $Flutter build windows --release --no-tree-shake-icons
  if ($LASTEXITCODE -ne 0) { exit 1 }
  Pop-Location
}

$out = Join-Path $RepoRoot $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 交付红线：**绝不允许把用户数据打进交付物**。
# 应用数据默认就在 exe 旁边的 `userdata\`（用户反馈 10），只要有人在本机跑过一次
# 这个 Release 目录里的 exe（冒烟测试也算），该目录就会被创建，甚至把旧版本
# `%APPDATA%` 下的真实库/截图搬进来。这里在打包前强制清掉并复核。
$userData = Join-Path $releaseDir "userdata"
if (Test-Path $userData) {
  Write-Host "清理构建输出里的用户数据目录：$userData（不得进交付物）"
  Remove-Item $userData -Recurse -Force
}
if (Test-Path $userData) {
  Write-Host "FAILED: userdata 仍然存在，拒绝打包（避免泄露用户数据）"
  exit 1
}

$zipPath = Join-Path $out ("quizsync-windows-portable-" + $Version + ".zip")

# M26（用户拍板）：随包带 VC++ 运行库，让「从没装过开发工具」的 Windows 也能直接双击运行。
# 按微软的 app-local 部署单位，把整个 `Microsoft.VC*.CRT\x64` 目录复制进 Release 目录 ——
# 不是只挑导入表里出现的那两三个：多出来的几个（msvcp140_1/_2/atomic_wait/codecvt_ids、
# concrt140、vcruntime140_1/threads）合计约 1.8 MB（zip 里约 0.7 MB），换来的是
# 「以后依赖升级引入新的 stdlib 分片」也不会再出现缺 DLL。zip 与安装包都从同一个目录取文件，
# 两份交付物自动一致；安装包那边由 installer.iss 的 `Source: {#ReleaseDir}\*` 自动带上。
$vcDir = Find-VcRuntimeDir
if (-not $vcDir) {
  Write-Host "FAILED: 找不到 VC++ 可再发行运行库（VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT）。" -ForegroundColor Red
  Write-Host "        本机能构建 Flutter Windows 就说明装了 Visual Studio，正常不该缺；"
  Write-Host "        拒绝在缺少运行库的情况下打包 —— 那样的交付物在干净机器上会缺 DLL 起不来。"
  exit 1
}
$vcDlls = @(Get-ChildItem -Path $vcDir -Filter *.dll -File)
if ($vcDlls.Count -lt 3) {
  Write-Host ("FAILED: " + $vcDir + " 里只有 " + $vcDlls.Count + " 个 DLL，不像是完整的 CRT 目录。") -ForegroundColor Red
  exit 1
}
Write-Host ("随包 VC 运行库：" + $vcDlls.Count + " 个，来自 " + $vcDir)
foreach ($d in $vcDlls) {
  Copy-Item -LiteralPath $d.FullName -Destination (Join-Path $releaseDir $d.Name) -Force
}
# 复制后逐一复核：静默失败过一次就够（交付物缺 DLL 是「用户双击没反应」级别的故障）
foreach ($d in $vcDlls) {
  $dest = Join-Path $releaseDir $d.Name
  if (-not (Test-Path $dest)) {
    Write-Host ("FAILED: " + $d.Name + " 没有复制到 " + $releaseDir) -ForegroundColor Red
    exit 1
  }
}
$vcMb = [math]::Round((($vcDlls | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
Write-Host ("VC 运行库合计 " + $vcMb + " MB（" + (($vcDlls | ForEach-Object { $_.Name }) -join ", ") + "）")

$zipFailed = $false
try {
  if (Test-Path $zipPath) {
    # 交付物很容易被解压工具占住：用户拿到上一轮的 zip 后常常正开着 Bandizip /
    # 资源管理器预览（实测：`Remove-Item` 与 `Rename-Item` 都报 WinError 32）。
    # 删不掉就重试几次，别让一次占用白跑整条构建链。
    for ($i = 1; $i -le 5; $i++) {
      try { Remove-Item $zipPath -Force; break }
      catch {
        if ($i -eq 5) { throw }
        Write-Host ("旧 zip 暂时删不掉（第 " + $i + " 次），2 秒后重试…")
        Start-Sleep -Seconds 2
      }
    }
  }
  Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath

  # 打包后再核对一次：zip 里不得出现 userdata。
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $leaked = @($archive.Entries | Where-Object { $_.FullName -like 'userdata*' })
    if ($leaked.Count -gt 0) {
      Write-Host ("FAILED: 便携版 zip 里混进了 userdata（" + $leaked.Count + " 项），拒绝交付")
      exit 1
    }
    # M26：VC 运行库必须真的进了 zip（交付物要在「没装过运行库」的机器上也能双击运行）
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    $missingVc = @($vcDlls | Where-Object { $entryNames -notcontains $_.Name } | ForEach-Object { $_.Name })
    if ($missingVc.Count -gt 0) {
      Write-Host ("FAILED: 便携版 zip 里缺少 VC 运行库：" + ($missingVc -join ", ") + "，拒绝交付")
      exit 1
    }
    Write-Host ("zip 内已含全部 " + $vcDlls.Count + " 个 VC 运行库")
  } finally {
    $archive.Dispose()
  }
  $size = (Get-Item $zipPath).Length / 1MB
  Write-Host ("portable zip: " + $zipPath + " (" + [math]::Round($size, 1) + " MB)")
} catch {
  # 便携版打不出来不该连累安装包（它才是「装上就能用」的那一份）：
  # 记下失败、继续编安装包，最后以非 0 退出 —— build_all.ps1 因此不会打印 ALL GREEN。
  $zipFailed = $true
  Write-Host ("FAILED: portable zip 打包失败 —— " + $_.Exception.Message)
  Write-Host ("提示：" + $zipPath + " 很可能正被解压工具 / 资源管理器占用，关掉它再重跑本脚本。")
  Write-Host "      注意：dist 里现有的那个 zip 仍是**上一轮的旧包**，不要当成本轮交付物。"
}

$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
  # 只在「标准安装位置」与显式环境变量里找（不写死开发机路径）。
  $candidates = @()
  if ($env:ISCC_PATH) { $candidates += $env:ISCC_PATH }
  $candidates += @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { $iscc = Get-Item $candidate; break }
  }
}
if ($iscc) {
  Write-Host ("Compiling installer with " + $iscc.FullName + " ...")
  # M47：版本号由本脚本传进去，installer.iss 不再自己写死一份（它保留了默认值兜底，
  # 单独手工编译时也能用）。
  & $iscc.FullName "/DAppVersion=$Version" (Join-Path $RepoRoot "tools\installer.iss")
  if ($LASTEXITCODE -ne 0) { Write-Host "installer compile FAILED"; exit 1 }
  $setupPath = Join-Path $out ("quizsync-windows-setup-" + $Version + ".exe")
  $setupSize = (Get-Item $setupPath).Length / 1MB
  Write-Host ("installer: " + $setupPath + " (" + [math]::Round($setupSize, 1) + " MB)")
} else {
  Write-Host "ISCC.exe not found; installer skipped (portable zip produced)."
}

# zip 打不出来时以非 0 退出（build_all.ps1 据此不打印 ALL GREEN）。
if ($zipFailed) { exit 1 }
