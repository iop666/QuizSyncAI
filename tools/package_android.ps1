# Package the release APKs into dist\ with the delivery naming:
#   dist\quizsync-android-<abi>-<version>.apk
#
# Why this file exists: build_all.ps1 used to stop after `flutter build apk`, so
# `dist\` kept whatever APK was copied there by hand earlier. The Windows side
# packages itself (package_windows.ps1) and the Android side silently went stale.
param(
  # M47：默认不写死版本 —— 留空时从 apps\android\pubspec.yaml 读（唯一来源）。
  [string]$Version = "",
  [string]$OutDir = "dist"
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Join-Path $RepoRoot "apps\android\pubspec.yaml"
  $m = [regex]::Match((Get-Content -Raw -Encoding UTF8 $pubspec), "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)")
  if (-not $m.Success) { Write-Host "FAILED: 读不出 apps\android\pubspec.yaml 的版本号" -ForegroundColor Red; exit 1 }
  $Version = $m.Groups[1].Value
}
$srcDir = Join-Path $RepoRoot "apps\android\build\app\outputs\flutter-apk"
$out = Join-Path $RepoRoot $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null

$abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
foreach ($abi in $abis) {
  $src = Join-Path $srcDir ("app-" + $abi + "-release.apk")
  if (-not (Test-Path $src)) {
    Write-Host ("FAILED: missing " + $src + " (run flutter build apk --split-per-abi --release first)")
    exit 1
  }
  $dest = Join-Path $out ("quizsync-android-" + $abi + "-" + $Version + ".apk")
  Copy-Item $src $dest -Force
  $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
  Write-Host ("apk " + $abi + ": " + $dest + " (" + $mb + " MB)")
}

# Sanity check: the delivered APKs must match the ones just built byte for byte.
foreach ($abi in $abis) {
  $src = Join-Path $srcDir ("app-" + $abi + "-release.apk")
  $dest = Join-Path $out ("quizsync-android-" + $abi + "-" + $Version + ".apk")
  $a = (Get-FileHash $src -Algorithm SHA256).Hash
  $b = (Get-FileHash $dest -Algorithm SHA256).Hash
  if ($a -ne $b) {
    Write-Host ("FAILED: " + $dest + " does not match the freshly built APK")
    exit 1
  }
}
Write-Host "apk: 3 ABI(s) copied to dist and verified"
