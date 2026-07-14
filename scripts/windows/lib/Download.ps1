# Download.ps1 - HTTP downloads and upgrade failure tips


function Download-File {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Msg = "Downloading",
        [string]$GithubToken = $null
    )

    if ($global:DryRun) {
        Log-Warn "[DRY RUN] Would download: $Url -> $Dest"
        return $true
    }

    Write-Host -NoNewline "$Msg... "

    $headers = @{}
    if ($GithubToken -and ($Url -like "*github.com*" -or $Url -like "*githubusercontent.com*")) {
        $headers["Authorization"] = "token $GithubToken"
    }

    try {
        # Ensure parent folder exists
        $parent = Split-Path -Parent $Dest
        if ($parent -and !(Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        # Prefer streaming download with byte progress on interactive consoles.
        $useProgress = $script:IsConsoleHost -and -not (Test-MillenniumQuiet)
        if ($useProgress) {
            Write-Progress -Activity $Msg -Status "Starting..." -PercentComplete 0
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "GET"
            $req.UserAgent = "millennium-helpers"
            if ($headers.ContainsKey("Authorization")) {
                $req.Headers["Authorization"] = $headers["Authorization"]
            }
            $resp = $req.GetResponse()
            $total = $resp.ContentLength
            $stream = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($Dest)
            $buffer = New-Object byte[] 81920
            $readTotal = [int64]0
            try {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fs.Write($buffer, 0, $read)
                    $readTotal += $read
                    if ($total -gt 0) {
                        $pct = [int](($readTotal * 100L) / $total)
                        Write-Progress -Activity $Msg -Status ("{0:N0} / {1:N0} bytes" -f $readTotal, $total) -PercentComplete $pct
                    } else {
                        Write-Progress -Activity $Msg -Status ("{0:N0} bytes" -f $readTotal) -PercentComplete -1
                    }
                }
            } finally {
                $fs.Dispose()
                $stream.Dispose()
                $resp.Dispose()
            }
            Write-Progress -Activity $Msg -Completed
        } else {
            if ($headers.Count -gt 0) {
                Invoke-WebRequest -Uri $Url -OutFile $Dest -Headers $headers -UseBasicParsing -ErrorAction Stop
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
            }
        }

        Write-Host -ForegroundColor Green "OK"
        return $true
    } catch {
        Write-Progress -Activity $Msg -Completed -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor Red "FAIL"
        Log-Error $_.Exception.Message
        return $false
    }
}


function Write-UpgradeFailureTips {
    param([string]$Detail = "")
    Write-Host ""
    if ($Detail) {
        Log-Error "Upgrade failed: $Detail"
    } else {
        Log-Error "Upgrade failed."
    }
    Write-Host "Next steps:"
    Write-Host "  * millennium upgrade -Rollback list   # list backups"
    Write-Host "  * millennium diag                     # check installation health"
    Write-Host "  * Re-run with -Yes if Steam close confirmation blocked the update"
}

# Suggest the closest known token for typos.
# Scoring (higher wins): 4 = prefix/extension, 3 = substring, else shared leading
# chars; subsequence matches (e.g. lst->list) score 3 minus length gap (floor 2).
# Returns $null unless bestScore >= 2 (avoids weak one-char coincidences).
