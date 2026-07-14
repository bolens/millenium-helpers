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

# Require Go .exe when the release zip embeds it.
$millenniumExe = Join-Path $winScripts 'millennium.exe'
if (Test-Path -LiteralPath $millenniumExe) {
  Install-ChocolateyPath -PathToInstall $winScripts -PathType 'User'
  Install-BinFile -Name 'millennium' -Path $millenniumExe
} else {
  throw 'millennium.exe (Go dispatcher) not found in release zip'
}

foreach ($pair in @(
    @{ Name = 'millennium-diag'; Args = 'diag' },
    @{ Name = 'millennium-mcp'; Args = 'mcp' },
    @{ Name = 'millennium-purge'; Args = 'purge' },
    @{ Name = 'millennium-repair'; Args = 'repair' },
    @{ Name = 'millennium-schedule'; Args = 'schedule' },
    @{ Name = 'millennium-theme'; Args = 'theme' },
    @{ Name = 'millennium-upgrade'; Args = 'upgrade' }
  )) {
  Install-BinFile -Name $pair.Name -Path $millenniumExe -Command "$($pair.Args) %*"
}
