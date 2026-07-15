# Millennium dispatcher Nushell completions (millennium <command> …)

def _millennium_dispatcher_commands [] {
  [ "diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp", "install", "uninstall", "help" ]
}

def _millennium_schedule_actions [] {
  [ "enable", "disable", "status", "setup", "config" ]
}

def _millennium_schedule_channels [] {
  [ "stable", "beta", "main", "get", "set", "list" ]
}

def _millennium_diag_actions [] {
  [ "doctor", "logs", "--fix" ]
}

def _millennium_theme_actions [] {
  [ "list", "install", "remove", "update" ]
}

export extern "millennium" [
  command?: string@"_millennium_dispatcher_commands"
  --version(-V)
  --help(-h)
]

export extern "millennium schedule" [
  action?: string@"_millennium_schedule_actions"
  channel?: string@"_millennium_schedule_channels"
  --cron(-c)     # Force use of crontab instead of systemd
  --system       # Linux: force systemd system units
  --user         # Linux: force systemd user units
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium upgrade" [
  --channel(-c): string # Update channel (stable, beta, main)
  --stable       # Alias for --channel stable
  --beta         # Alias for --channel beta
  --main         # Alias for --channel main
  --rollback(-r): string # Rollback to a specific version or list backups
  --file: string # Install from a local archive
  --sha256: string # Expected SHA-256 of --file archive
  --insecure-skip-verify # Skip archive checksum verification
  --all-users    # Unix: apply install for all users
  --force(-f)    # Force reinstall
  --yes(-y)      # Skip confirmation when closing Steam
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium diag" [
  action?: string@"_millennium_diag_actions"
  --force        # Force all doctor repairs even if system is healthy
  --json         # Output diagnostics report in structured JSON format
  --follow(-l)   # Follow real-time log output
  --yes(-y)      # Skip confirmation when doctor closes Steam
  --share(-s)    # Upload diagnostic report to a pastebin
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium theme" [
  action?: string@"_millennium_theme_actions"
  theme?: string # Theme name or GitHub repository URL
  --all(-a) # Update all themes (only applicable if action is update)
  --json # Output list command results as structured JSON
  --yes(-y) # Skip confirmation when removing a theme
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium repair" [
  --skip-theme(-s) # Skip theme refresh during repair
  --yes(-y)      # Skip confirmation when closing Steam
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium purge" [
  --dry-run(-d)  # Simulation mode
  --quiet(-q)    # Suppress informational output
  --yes(-y)      # Skip confirmation prompt
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium mcp" [
  --register(-r) # Register MCP server with Claude Desktop, Windsurf, and Cursor
  --version(-V)  # Show version information
  --help(-h)     # Show help message
]

export extern "millennium install" [
  --track: string # Helpers install track (release, main, tag, checkout)
  --tag: string   # Install a specific release tag
  --allow-unsigned-main # Allow tip-of-main unsigned archive
  --prefix: string
  --target-dir: string
  --lib-dir: string
  --source-root: string
  --skip-wizard  # Do not launch schedule setup
  --dry-run(-d)
  --force(-f)
  --version(-V)
  --help(-h)
]

export extern "millennium uninstall" [
  --purge(-p)    # Also purge Millennium client
  --prefix: string
  --target-dir: string
  --lib-dir: string
  --dry-run(-d)
  --version(-V)
  --help(-h)
]
