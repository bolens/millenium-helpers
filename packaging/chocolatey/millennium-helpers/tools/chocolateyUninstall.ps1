$ErrorActionPreference = 'Stop'

foreach ($name in @(
    'millennium',
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
