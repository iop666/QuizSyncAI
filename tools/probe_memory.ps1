# M25（优化轮 · 内存探针）：对**真实 release exe** 采样 RSS / 私有内存 / 句柄 / GDI / USER。
#
# 为什么要这个脚本：M14 那次「悬浮球内存飙升」是用一个临时探针量出来的（163.5 → 216.6 MB 一直涨、
# 加缓存后 159.2 → 175.0 MB 停住），但探针本身没留下来，所以每次都要重做。这里把它固化成可重复的工具：
# 同样的命令、同样的口径，改动前后各跑一次就能比较。
#
# 三个刻意的设计（都是踩过的坑）：
#   1. **绝不动用户正在运行的那一份**：发现已有 quizsync_desktop 在跑就直接 ABORT，
#      既不杀进程也不复用它的窗口（2026-09-17 事故：按进程名批量杀进程会连带杀掉 harness 与 MCP）。
#   2. **在临时目录里跑副本**：应用会把数据写到 exe 旁边的 `userdata\`（M11 红线），
#      直接在 build 目录里跑一次就会污染构建产物；这里先整目录复制到临时工作区，跑完删掉。
#   3. 采样口径固定：先 settle 再按 IntervalMs 采样 SampleSeconds 秒，同时报告
#      「首末差值」与「后半段相对前半段的漂移」—— 只报首末容易被一次 GC 抖动误导。
#
# 用法：
#   powershell -File tools\probe_memory.ps1
#   powershell -File tools\probe_memory.ps1 -SettleSeconds 10 -SampleSeconds 60 -KeepWork
param(
  [string]$ReleaseDir = "",
  [int]$SettleSeconds = 6,
  [int]$SampleSeconds = 20,
  [int]$IntervalMs = 2000,
  # 探针工作目录：显式传参 > `$env:QS_PROBE_DIR` > 系统临时目录。不写死开发机路径。
  [string]$WorkRoot = $(if ($env:QS_PROBE_DIR) { $env:QS_PROBE_DIR } else { Join-Path $env:TEMP "QuizSyncProbe" }),
  [switch]$KeepWork
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ($ReleaseDir -eq "") {
  $ReleaseDir = Join-Path $RepoRoot "apps\desktop\build\windows\x64\runner\Release"
}
$exeSrc = Join-Path $ReleaseDir "quizsync_desktop.exe"
if (-not (Test-Path $exeSrc)) {
  Write-Host ("FAILED: 找不到 " + $exeSrc + "（先跑 flutter build windows --release 或 tools\build_all.ps1）") -ForegroundColor Red
  exit 2
}

# ---- 1) 不碰用户正在运行的实例 ----
$running = @(Get-Process -Name "quizsync_desktop" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
  $pids = ($running | ForEach-Object { $_.Id }) -join ", "
  Write-Host ("ABORT: 本机已有 quizsync_desktop 在运行（PID " + $pids + "）。") -ForegroundColor Red
  Write-Host "       请先自己关掉它再跑探针 —— 探针绝不替你杀进程（按进程名杀会连带打掉 harness / MCP）。" -ForegroundColor Red
  exit 3
}

# ---- 2) 在临时工作区跑副本（数据写在副本旁边，不污染 build 目录） ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class QuizSyncGuiRes {
  [DllImport("user32.dll")]
  public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
}
"@

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$work = Join-Path $WorkRoot ($stamp + "-rss-probe")
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -Path (Join-Path $ReleaseDir "*") -Destination $work -Recurse -Force
$exe = Join-Path $work "quizsync_desktop.exe"
Write-Host ("工作副本：" + $work) -ForegroundColor Cyan

$proc = Start-Process -FilePath $exe -WorkingDirectory $work -PassThru
$start = Get-Date
Write-Host ("已启动 PID " + $proc.Id + "，settle " + $SettleSeconds + " 秒…")
Start-Sleep -Seconds $SettleSeconds

if ($proc.HasExited) {
  Write-Host ("FAILED: 进程在 settle 期间就退出了（ExitCode=" + $proc.ExitCode + "）") -ForegroundColor Red
  Write-Host "        多半是缺 VC 运行库或 data\ 载荷不全；看 Windows 事件查看器的 faulting module。"
  exit 1
}

# ---- 3) 采样 ----
$samples = @()
$deadline = (Get-Date).AddSeconds($SampleSeconds)
while ((Get-Date) -lt $deadline) {
  $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
  if ($null -eq $p) { break }
  $samples += [pscustomobject]@{
    T   = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    WS  = [math]::Round($p.WorkingSet64 / 1MB, 1)
    Priv= [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
    Hnd = $p.HandleCount
    GDI = [QuizSyncGuiRes]::GetGuiResources($p.Handle, 0)
    USR = [QuizSyncGuiRes]::GetGuiResources($p.Handle, 1)
  }
  Start-Sleep -Milliseconds $IntervalMs
}

if ($samples.Count -eq 0) {
  Write-Host "FAILED: 一条样本都没采到（进程已退出？）" -ForegroundColor Red
  exit 1
}

Write-Host ""
$samples | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$first = $samples[0]
$last = $samples[$samples.Count - 1]
$half = [int]($samples.Count / 2)
$avgFirst = [math]::Round((($samples[0..([math]::Max(0, $half - 1))] | Measure-Object -Property WS -Average).Average), 1)
$avgSecond = [math]::Round((($samples[$half..($samples.Count - 1)] | Measure-Object -Property WS -Average).Average), 1)
$wsMin = ($samples | Measure-Object -Property WS -Minimum).Minimum
$wsMax = ($samples | Measure-Object -Property WS -Maximum).Maximum

Write-Host ""
Write-Host "== 结论 ==" -ForegroundColor Cyan
Write-Host ("RSS     首 " + $first.WS + " MB → 末 " + $last.WS + " MB（差 " + [math]::Round($last.WS - $first.WS, 1) + " MB）；min " + $wsMin + " / max " + $wsMax)
Write-Host ("RSS     前半段均值 " + $avgFirst + " MB → 后半段均值 " + $avgSecond + " MB（漂移 " + [math]::Round($avgSecond - $avgFirst, 1) + " MB）")
Write-Host ("私有内存 首 " + $first.Priv + " MB → 末 " + $last.Priv + " MB")
Write-Host ("句柄     " + $first.Hnd + " → " + $last.Hnd + "；GDI " + $first.GDI + " → " + $last.GDI + "；USER " + $first.USR + " → " + $last.USR)
Write-Host ("采样     " + $samples.Count + " 点 / " + $SampleSeconds + " 秒（间隔 " + $IntervalMs + " ms），样本文件：无（只打印）")

# ---- 4) 收尾：只杀自己启动的那个 PID ----
if (-not $proc.HasExited) {
  $proc.Kill()
  $null = $proc.WaitForExit(5000)
}
Write-Host ""
$userdata = Join-Path $work "userdata"
if (Test-Path $userdata) {
  $n = (Get-ChildItem -Recurse -File $userdata | Measure-Object).Count
  Write-Host ("提示：副本里生成了 userdata（" + $n + " 个文件）—— 这正是**不能**在 build 目录里直接跑 exe 的原因。") -ForegroundColor Yellow
}
if ($KeepWork) {
  Write-Host ("保留工作副本：" + $work)
} else {
  for ($i = 1; $i -le 5; $i++) {
    try { Remove-Item $work -Recurse -Force -ErrorAction Stop; break }
    catch {
      if ($i -eq 5) { Write-Host ("清理工作副本失败（" + $work + "），留着不影响结果。") -ForegroundColor Yellow }
      Start-Sleep -Seconds 2
    }
  }
  if (-not (Test-Path $work)) { Write-Host "工作副本已清理。" }
}
exit 0
