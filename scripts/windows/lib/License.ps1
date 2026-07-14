# License.ps1 - Install Project Millennium MIT notice next to client binaries
# Docs: docs/licensing.md
# Upstream: https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md


function Install-MillenniumLicense {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestDir
    )
    if (-not (Test-Path -Path $DestDir -PathType Container)) {
        Log-Warn "Cannot install Millennium LICENSE — missing directory: $DestDir"
        return
    }
    $dest = Join-Path -Path $DestDir -ChildPath "LICENSE"
    $candidates = @()
    $winDir = $script:MillenniumHelpersWinDir
    if (-not $winDir -and $PSScriptRoot) {
        $winDir = Split-Path -Parent -Path $PSScriptRoot
    }
    if ($winDir) {
        $candidates += (Join-Path -Path $winDir -ChildPath "..\..\third_party\MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $winDir -ChildPath "MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $winDir -ChildPath "third_party\MILLENNIUM-LICENSE.md")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\third_party\MILLENNIUM-LICENSE.md")
    }
    if ($env:USERPROFILE) {
        $candidates += (Join-Path -Path $env:USERPROFILE -ChildPath ".millennium-helpers\bin\MILLENNIUM-LICENSE.md")
    }

    foreach ($src in $candidates) {
        if ($src -and [System.IO.File]::Exists($src)) {
            try {
                Copy-Item -Path $src -Destination $dest -Force
                return
            } catch {}
        }
    }

    try {
        $url = "https://raw.githubusercontent.com/SteamClientHomebrew/Millennium/main/LICENSE.md"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ((Test-Path -Path $dest) -and ((Get-Item $dest).Length -gt 0)) {
            return
        }
    } catch {}

    # Literal here-string: expandable @"…"@ breaks on "Software"/"AS IS" under Windows PowerShell 5.1.
    $fallback = @'
MIT License

Copyright (c) 2026 Project Millennium

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'@
    try {
        Set-Content -Path $dest -Value $fallback -Encoding utf8 -Force
    } catch {}
}

if (!$env:LOCALAPPDATA) {
    $env:LOCALAPPDATA = Join-Path -Path $env:HOME -ChildPath ".config"
}
