$ErrorActionPreference = 'Stop'

Uninstall-BinFile -Name 'millennium'
# Legacy long-name PATH shims from older packages.
foreach ($name in @(
    'millennium-diag',
    'millennium-mcp',
    'millennium-purge',
    'millennium-repair',
    'millennium-schedule',
    'millennium-theme',
    'millennium-upgrade'
  )) {
  Uninstall-BinFile -Name $name
}

try {
  Unregister-ScheduledTask -TaskName 'MillenniumUpdate' -Confirm:$false -ErrorAction SilentlyContinue
} catch {}
