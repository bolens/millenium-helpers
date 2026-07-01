# Millennium Helper Script Nushell Completions

# Run Millennium theme and hook link repair
export extern "millennium-repair" [
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

# Upgrade Millennium client using stable channel
export extern "millennium-upgrade-stable" [
  --force(-f)    # Force reinstall
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

# Upgrade Millennium client using beta channel
export extern "millennium-upgrade-beta" [
  --force(-f)    # Force reinstall
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

# Manage daily auto-update scheduler
export extern "millennium-schedule" [
  action?: string@"_millennium_schedule_actions" # Scheduler action (enable, disable, status)
  channel?: string@"_millennium_schedule_channels" # Update channel (stable, beta)
  --help(-h)     # Show help message
]

def _millennium_schedule_actions [] {
  [ "enable", "disable", "status" ]
}

def _millennium_schedule_channels [] {
  [ "stable", "beta" ]
}

# Purge Millennium files and restore original Steam client
export extern "millennium-purge" [
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

# Diagnostics utility for Millennium environment
export extern "millennium-diag" [
  action?: string@"_millennium_diag_actions" # Run diagnostics doctor automatically
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

def _millennium_diag_actions [] {
  [ "doctor", "--fix" ]
}

# Manage Millennium skins and themes
export extern "millennium-theme" [
  action?: string@"_millennium_theme_actions" # Theme action (list, install, remove, update)
  theme?: string # Theme name or GitHub repository URL
  --all  # Update all themes (only applicable if action is update)
  --dry-run(-d)  # Simulation mode
  --help(-h)     # Show help message
]

def _millennium_theme_actions [] {
  [ "list", "install", "remove", "update" ]
}

# Run Model Context Protocol (MCP) server
export extern "millennium-mcp" [
  --help(-h)     # Show help message
]

