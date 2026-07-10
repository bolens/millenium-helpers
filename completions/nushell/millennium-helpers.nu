# Millennium Helper Script Nushell Completions

# Run Millennium theme and hook link repair
export extern "millennium-repair" [
  --skip-theme(-s) # Skip theme refresh during repair
  --dry-run(-d)  # Simulation mode
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

# Upgrade Millennium client using specified channel
export extern "millennium-upgrade" [
  --channel(-c): string # Update channel (stable, beta)
  --stable       # Alias for --channel stable
  --beta         # Alias for --channel beta
  --rollback(-r): string # Rollback to a specific version or list backups
  --file: string # Install from a local archive
  --force(-f)    # Force reinstall
  --dry-run(-d)  # Simulation mode
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

# Manage daily auto-update scheduler
export extern "millennium-schedule" [
  action?: string@"_millennium_schedule_actions" # Scheduler action
  channel?: string@"_millennium_schedule_channels" # Update channel or config action
  --dry-run(-d)  # Simulation mode
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

def _millennium_schedule_actions [] {
  [ "enable", "disable", "status", "setup", "config" ]
}

def _millennium_schedule_channels [] {
  [ "stable", "beta", "get", "set", "list" ]
}

# Purge Millennium files and restore original Steam client
export extern "millennium-purge" [
  --dry-run(-d)  # Simulation mode
  --yes(-y)      # Skip confirmation prompt
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

# Diagnostics utility for Millennium environment
export extern "millennium-diag" [
  action?: string@"_millennium_diag_actions" # Diagnostics command
  --force        # Force all doctor repairs even if system is healthy
  --json         # Output diagnostics report in structured JSON format
  --follow(-l)   # Follow real-time log output
  --share(-s)    # Upload diagnostic report to a pastebin
  --dry-run(-d)  # Simulation mode
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

def _millennium_diag_actions [] {
  [ "doctor", "logs", "--fix" ]
}

# Manage Millennium skins and themes
export extern "millennium-theme" [
  action?: string@"_millennium_theme_actions" # Theme action (list, install, remove, update)
  theme?: string # Theme name or GitHub repository URL
  --all(-a) # Update all themes (only applicable if action is update)
  --json # Output list command results in structured JSON format
  --dry-run(-d)  # Simulation mode
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

def _millennium_theme_actions [] {
  [ "list", "install", "remove", "update" ]
}

# Run Model Context Protocol (MCP) server
export extern "millennium-mcp" [
  --register(-r) # Register MCP server with Claude Desktop and Windsurf
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]
