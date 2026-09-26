# 生成 release 签名 keystore（仅首次；之后复用）。
# 口令不写进任何脚本/仓库——构建时经 key.properties（已 gitignore）读取。
$ErrorActionPreference = "Stop"
if ($args.Count -lt 4) {
  Write-Host "用法: gen_keystore.ps1 <输出路径> <别名> <口令> <有效天数(默认 10950)>"
  exit 1
}
$out = $args[0]; $alias = $args[1]; $storepass = $args[2]
 $validity = if ($args.Count -ge 4) { $args[3] } else { 10950 }
# M47：keytool 先按 PATH / JAVA_HOME 找，找不到再用本机安装位置。
$jdk = $null
$cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
if ($cmd) { $jdk = $cmd.Source }
if (-not $jdk -and $env:JAVA_HOME) {
  $candidate = Join-Path $env:JAVA_HOME "bin\keytool.exe"
  if (Test-Path $candidate) { $jdk = $candidate }
}
if (-not $jdk) {
  # 只认 PATH（`keytool` 命令本身）与环境变量，不写死开发机的 JDK 路径。
  $cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
  if ($cmd) { $jdk = $cmd.Source }
}
if (-not $jdk) {
  Write-Host "FAILED: 找不到 keytool（PATH / JAVA_HOME 都没有）" -ForegroundColor Red
  exit 1
}
& $jdk -genkeypair -v `
  -keystore $out -alias $alias `
  -keyalg RSA -keysize 2048 -validity $validity `
  -storepass $storepass -keypass $storepass `
  -dname "CN=QuizSync AI, OU=Personal, O=Personal, C=CN"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "keystore 已生成：$out"
Write-Host "请把口令保存在密码管理器中；keystore 备份说明见 README。"
