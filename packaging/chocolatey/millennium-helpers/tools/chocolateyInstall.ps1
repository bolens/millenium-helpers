$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '3.1.0'
$url = "https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-v$version-windows-amd64.zip"
$checksum = '78457788321f502815aa7be0b24fcbe53c64f31d1873bfea3177e949a92a9c0c'

$packageArgs = @{
  packageName   = 'millennium-helpers'
  unzipLocation = Join-Path $toolsDir 'payload'
  url           = $url
  checksum      = $checksum
  checksumType  = 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

$payload = $packageArgs.unzipLocation
$winScripts = Join-Path $payload 'scripts\windows'
if (!(Test-Path -LiteralPath $winScripts)) {
  throw "Unexpected archive layout: missing scripts\windows under $payload"
}

# Require Go .exe when the release zip embeds it.
$millenniumExe = Join-Path $winScripts 'millennium.exe'
if (Test-Path -LiteralPath $millenniumExe) {
  Install-ChocolateyPath -PathToInstall $winScripts -PathType 'User'
  Install-BinFile -Name 'millennium' -Path $millenniumExe
} else {
  throw 'millennium.exe (Go dispatcher) not found in release zip'
}
