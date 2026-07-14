# Config.ps1 - Helpers config file ACL protection


function Protect-HelpersConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -Path $Path -PathType Leaf)) {
        return
    }

    $onWindows = $false
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $onWindows = $true
        } elseif (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
            $onWindows = [bool]$IsWindows
        } elseif ($env:OS -eq 'Windows_NT') {
            $onWindows = $true
        }
    } catch {
        $onWindows = ($env:OS -eq 'Windows_NT')
    }
    if (-not $onWindows) {
        return
    }

    try {
        $acl = Get-Acl -Path $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            $null = $acl.RemoveAccessRule($rule)
        }
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            'FullControl',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        Set-Acl -Path $Path -AclObject $acl
    } catch {
        Log-Warn "Could not restrict ACL on ${Path}: $($_.Exception.Message)"
    }
}

# Extract a zip into DestinationPath, rejecting absolute paths and '..' (zip-slip).
