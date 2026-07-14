$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '2.6.2'
$url = "https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-v$version-windows-amd64.zip"
$checksum = '3d1fabe638ce2e990b7b0007ef77dd4afa1668fd558010758f0213c1c8826506'

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

# Prefer Go .exe when the release zip embeds it; otherwise keep PowerShell dispatcher.
$millenniumExe = Join-Path $winScripts 'millennium.exe'
$millenniumPs1 = Join-Path $winScripts 'millennium.ps1'
if (Test-Path -LiteralPath $millenniumExe) {
  Install-ChocolateyPath -PathToInstall $winScripts -PathType 'User'
  Install-BinFile -Name 'millennium' -Path $millenniumExe
} elseif (Test-Path -LiteralPath $millenniumPs1) {
  Install-ChocolateyPath -PathToInstall $winScripts -PathType 'User'
  Install-BinFile -Name 'millennium' -Path $millenniumPs1
} else {
  throw 'Neither millennium.exe nor millennium.ps1 found in release zip'
}

foreach ($pair in @(
    @{ Name = 'millennium-diag'; File = 'millennium-diag.ps1' },
    @{ Name = 'millennium-mcp'; File = 'millennium-mcp.ps1' },
    @{ Name = 'millennium-purge'; File = 'millennium-purge.ps1' },
    @{ Name = 'millennium-repair'; File = 'millennium-repair.ps1' },
    @{ Name = 'millennium-schedule'; File = 'millennium-schedule.ps1' },
    @{ Name = 'millennium-theme'; File = 'millennium-theme.ps1' },
    @{ Name = 'millennium-upgrade'; File = 'millennium-upgrade.ps1' }
  )) {
  $p = Join-Path $winScripts $pair.File
  if (Test-Path -LiteralPath $p) {
    Install-BinFile -Name $pair.Name -Path $p
  }
}
