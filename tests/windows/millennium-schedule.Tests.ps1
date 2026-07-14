Describe "Schedule CLI Manager" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        # Config + status + enable/disable thin-wrap to Go.
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) {
                throw "Go toolchain required for schedule config/status thin-wrap tests"
            }
            $ver = [System.IO.File]::ReadAllText((Join-Path $repoRoot "VERSION")).Trim()
            Push-Location (Join-Path $repoRoot "go")
            try {
                & go build "-ldflags=-X github.com/bolens/millenium-helpers/internal/version.Version=$ver" `
                    -o $outExe ./cmd/millennium
                if ($LASTEXITCODE -ne 0) { throw "go build failed for millennium.exe" }
            } finally {
                Pop-Location
            }
        }
        function Register-ScheduledTask { }
        function Get-ScheduledTask { }
        function New-ScheduledTaskAction { }
        function New-ScheduledTaskTrigger { }
        function New-ScheduledTaskSettingsSet { }
        function Get-Content {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [string]$Path,
                [switch]$Raw,
                [string]$LiteralPath
            )
            $p = if ($LiteralPath) { $LiteralPath } else { $Path }
            if ($p -like "*config.json*") {
                # Defer to real Get-Content so config tests can read written files.
                return Microsoft.PowerShell.Management\Get-Content -LiteralPath $p -Raw:$Raw
            }
            if ($p -like "*VERSION*") {
                return "3.0.0"
            }
            return Microsoft.PowerShell.Management\Get-Content @PSBoundParameters
        }
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*enable*"
            $out | Should -BeLike "*setup*"
            $out | Should -BeLike "*-DryRun*"
            $out | Should -BeLike "*GNU-style*"
        }

        It "Prints version with -Version" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-schedule*"
        }

        It "Suggests closest command on typo" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript stauts *>&1) | Out-String
            $out | Should -BeLike "*Unknown command*"
            $out | Should -BeLike "*Did you mean*status*"
        }
    }

    Context "status via Go thin-wrap" {
        It "Reports disabled scheduler when MillenniumUpdate task is absent" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript status *>&1) | Out-String
            $out | Should -BeLike "*Scheduler disabled*"
            $out | Should -BeLike "*millennium schedule enable*"
        }
    }

    Context "Wizard setup via Go" {
        It "Dry-run wizard announces config and tips" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $tempConfigDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("pest_wiz_" + [guid]::NewGuid().ToString("n"))
            New-Item -ItemType Directory -Force -Path $tempConfigDir | Out-Null
            $env:LOCALAPPDATA = $tempConfigDir
            $env:FORCE_WIZARD = "true"
            try {
                $out = ("1`nn`n`n" | & $scheduleScript setup -DryRun *>&1) | Out-String
                $out | Should -BeLike "*Configuration Wizard*"
                $out | Should -BeLike "*DRY RUN*"
                $out | Should -BeLike "*backup_limit*"
            } finally {
                Remove-Item -Path $tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item Env:FORCE_WIZARD -ErrorAction SilentlyContinue
            }
        }
    }

    Context "config get/set/list" {
        BeforeEach {
            $script:tempConfigDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mh_sched_cfg_" + [guid]::NewGuid().ToString("n"))
            $env:LOCALAPPDATA = $script:tempConfigDir
            $cfgDir = Join-Path $script:tempConfigDir "millennium-helpers"
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
            '{"update_channel":"stable","github_token":"tok1234","backup_limit":3}' |
                Set-Content -Path (Join-Path $cfgDir "config.json") -Encoding utf8
        }
        AfterEach {
            Remove-Item -Path $script:tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Lists config including backup keys" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript config list *>&1) | Out-String
            $out | Should -BeLike "*update_channel*"
            $out | Should -BeLike "*backup_limit*"
            $out | Should -BeLike "*github_token*"
        }

        It "Sets update_channel to main" {
            $prevDry = $global:DryRun
            $global:DryRun = $false
            try {
                $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
                & $scheduleScript config set update_channel main *>&1 | Out-Null
                $cfgPath = Join-Path $env:LOCALAPPDATA "millennium-helpers\config.json"
                $raw = Microsoft.PowerShell.Management\Get-Content -LiteralPath $cfgPath -Raw
                $data = $raw | ConvertFrom-Json
                $data.update_channel | Should -Be "main"
                $data.backup_limit | Should -Be 3
            } finally {
                $global:DryRun = $prevDry
            }
        }

        It "Gets a config value" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript config get update_channel *>&1) | Out-String
            $out.Trim() | Should -Be "stable"
        }
    }

    Context "enable task dry-run via Go" {
        It "Dry-run announces Task Scheduler registration for the channel" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript enable beta -DryRun *>&1) | Out-String
            $out | Should -BeLike "*DRY RUN*"
            $out | Should -BeLike "*Would register*"
            $out | Should -BeLike "*beta*"
        }
    }
}
