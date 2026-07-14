# Archive.ps1 - Zip extraction with zip-slip rejection


function Expand-SafeArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    if (!(Test-Path -LiteralPath $Path)) {
        throw "Zip archive not found: $Path"
    }
    if (!(Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
    }
    $destFull = [System.IO.Path]::GetFullPath($DestinationPath)
    if (-not $destFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $destFull += [System.IO.Path]::DirectorySeparatorChar
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($name.StartsWith('/') -or ($name.Length -ge 2 -and $name[1] -eq ':')) {
                throw "Refusing zip member with unsafe path: $($entry.FullName)"
            }
            $parts = $name.Split('/')
            if ($parts | Where-Object { $_ -eq '..' }) {
                throw "Refusing zip member with path traversal: $($entry.FullName)"
            }
            $target = [System.IO.Path]::GetFullPath((Join-Path -Path $DestinationPath -ChildPath ($name -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            if (-not $target.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase) -and
                $target.TrimEnd('\') -ne $destFull.TrimEnd('\')) {
                throw "Refusing zip member outside extract root: $($entry.FullName)"
            }
        }
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($name) -or $name.EndsWith('/')) {
                $dirRel = $name.TrimEnd('/')
                if ($dirRel) {
                    $dirPath = Join-Path -Path $DestinationPath -ChildPath ($dirRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                    if (!(Test-Path -LiteralPath $dirPath)) {
                        New-Item -ItemType Directory -Force -Path $dirPath | Out-Null
                    }
                }
                continue
            }
            $outPath = Join-Path -Path $DestinationPath -ChildPath ($name -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $outDir = Split-Path -Parent -Path $outPath
            if (!(Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
        }
    } finally {
        $zip.Dispose()
    }
}
