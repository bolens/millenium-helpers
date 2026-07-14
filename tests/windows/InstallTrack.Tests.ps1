Describe "InstallTrack helpers" {
    BeforeAll {
        $winLib = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows\lib"
        . (Join-Path $winLib 'InstallTrack.ps1')
    }

    It "Resolves main and tag tracks (versioned windows-amd64 asset)" {
        $m = Resolve-HelpersInstallTrack -Track main -Platform windows
        $m.Track | Should -Be 'main'
        $m.Url | Should -BeLike '*archive/refs/heads/main.zip'
        $m.NeedsSha | Should -Be $false

        $t = Resolve-HelpersInstallTrack -Track tag -Tag '2.5.0' -Platform windows
        $t.Track | Should -Be 'tag'
        $t.Ref | Should -Be 'v2.5.0'
        $t.Url | Should -BeLike '*releases/download/v2.5.0/millennium-helpers-v2.5.0-windows-amd64.zip'
        $t.NeedsSha | Should -Be $true

        Get-HelpersBinAssetName -Version '1.2.3' -Platform windows |
            Should -Be 'millennium-helpers-v1.2.3-windows-amd64.zip'
    }

    It "Writes and migrates install-meta.json" {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-meta-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            Write-HelpersInstallMeta -InstallRoot $temp -Track release -Ref 'v1.0.0' -Version '1.0.0'
            $metaPath = Join-Path $temp 'install-meta.json'
            Test-Path $metaPath | Should -Be $true
            $meta = Read-HelpersInstallMeta -InstallRoot $temp
            $meta.track | Should -Be 'release'
            $meta.ref | Should -Be 'v1.0.0'

            # Idempotent when meta exists
            $again = Migrate-HelpersInstallMetaIfNeeded -InstallRoot $temp -Method manual
            $again | Should -Be $false

            $legacy = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-legacy-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $legacy | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $legacy 'bin') | Out-Null
            Set-Content -Path (Join-Path $legacy 'bin\VERSION') -Value "3.0.0"
            $migrated = Migrate-HelpersInstallMetaIfNeeded -InstallRoot $legacy -Method 'scoop-git'
            $migrated | Should -Be $true
            $lm = Read-HelpersInstallMeta -InstallRoot $legacy
            $lm.track | Should -Be 'main'
            $lm.migrated_from | Should -Be 'legacy'
            Remove-Item -Path $legacy -Recurse -Force
        } finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Windows Installer track flags" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $env:PSTESTS = "true"
    }

    It "Documents -Track and -Tag in -Help" {
        $installScript = Join-Path -Path $winScriptDir -ChildPath "install.ps1"
        $out = (& $installScript -Help *>&1) | Out-String
        $out | Should -BeLike "*-Track*"
        $out | Should -BeLike "*-Tag*"
    }

    It "Accepts -DryRun -Track main without error" {
        $installScript = Join-Path -Path $winScriptDir -ChildPath "install.ps1"
        $tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("pester_track_" + [guid]::NewGuid().ToString('n'))
        $old = $env:USERPROFILE
        $env:USERPROFILE = $tempHome
        try {
            $out = (& $installScript -DryRun -Track main *>&1) | Out-String
            $out | Should -BeLike "*DRY RUN*"
        } finally {
            $env:USERPROFILE = $old
            Remove-Item -Path $tempHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
