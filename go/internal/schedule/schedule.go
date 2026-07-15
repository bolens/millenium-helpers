package schedule

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/suggest"
)

// Options holds parsed schedule argv (excluding schedule config — handled separately).
type Options struct {
	Action       string // enable|disable|status|setup|pre-update|post-update|""
	Channel      string
	Cron         bool
	DryRun       bool
	Quiet        bool
	Help         bool
	Version      bool
	SystemdScope SystemdScope // "", "system", or "user" (Linux; auto when empty)
}

// ParseArgs parses millennium schedule argv.
func ParseArgs(args []string) (Options, error) {
	var o Options
	o.Cron = forceCronDefault()
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "-h", "--help", "-Help":
			o.Help = true
		case "-V", "--version", "-Version":
			o.Version = true
		case "-d", "--dry-run", "-DryRun":
			o.DryRun = true
		case "-q", "--quiet", "-Quiet":
			o.Quiet = true
		case "-c", "--cron":
			if runtime.GOOS == "windows" {
				return o, fmt.Errorf("Error: --cron is not supported on Windows.")
			}
			o.Cron = true
		case "--system":
			if runtime.GOOS != "linux" {
				return o, fmt.Errorf("Error: --system is only supported on Linux.")
			}
			if o.SystemdScope == ScopeUser {
				return o, fmt.Errorf("Error: cannot combine --system and --user.")
			}
			o.SystemdScope = ScopeSystem
		case "--user":
			if runtime.GOOS != "linux" {
				return o, fmt.Errorf("Error: --user is only supported on Linux.")
			}
			if o.SystemdScope == ScopeSystem {
				return o, fmt.Errorf("Error: cannot combine --system and --user.")
			}
			o.SystemdScope = ScopeUser
		case "enable", "disable", "status", "setup", "pre-update", "post-update", "config":
			if o.Action != "" {
				return o, fmt.Errorf("Error: multiple schedule actions (%s and %s).", o.Action, a)
			}
			o.Action = a
			if a == "enable" && i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				next := args[i+1]
				if next == "stable" || next == "beta" || next == "main" {
					i++
					o.Channel = next
				}
			}
		default:
			if strings.HasPrefix(a, "-") {
				return o, fmt.Errorf("Error: unknown option %s", a)
			}
			if o.Action == "enable" && o.Channel == "" && (a == "stable" || a == "beta" || a == "main") {
				o.Channel = a
				continue
			}
			if o.Action == "enable" && o.Channel == "" {
				return o, fmt.Errorf("Error: Unknown channel '%s'. Use stable, beta, or main.", a)
			}
			cmds := []string{"enable", "disable", "status", "setup", "pre-update", "post-update", "config"}
			if s := suggest.Closest(a, cmds); s != "" {
				return o, fmt.Errorf("Error: Unknown command '%s'.\nDid you mean '%s'?", a, s)
			}
			return o, fmt.Errorf("Error: Unknown command '%s'.", a)
		}
	}
	return o, nil
}

func forceCronDefault() bool {
	if runtime.GOOS == "darwin" || runtime.GOOS == "windows" {
		return false
	}
	if st, err := os.Stat("/run/systemd/system"); err == nil && st.IsDir() {
		return false
	}
	return true
}

// ResolveChannel returns enable channel from flag, else config, else stable.
func ResolveChannel(explicit string) string {
	if explicit == "stable" || explicit == "beta" || explicit == "main" {
		return explicit
	}
	data, err := config.Load()
	if err == nil {
		if ch := config.Get(data, "update_channel"); ch == "stable" || ch == "beta" || ch == "main" {
			return ch
		}
	}
	return "stable"
}

// NeedsLegacy reports actions that still require shell/PS (none — all native).
func NeedsLegacy(o Options) bool {
	_ = o
	return false
}

// RunCLI runs native schedule actions.
func RunCLI(o Options) int {
	if o.Help || o.Action == "" {
		fmt.Print(helpText())
		return 0
	}
	if o.DryRun && o.Action != "pre-update" && o.Action != "post-update" && o.Action != "setup" {
		fmt.Println("=== DRY RUN MODE: No changes will be made ===")
	}
	switch o.Action {
	case "status":
		fmt.Print(FormatStatus(CollectStatus()))
		return 0
	case "enable":
		return runEnable(ResolveChannel(o.Channel), o.Cron, o.DryRun, o.Quiet, o.SystemdScope)
	case "disable":
		return runDisable(o.DryRun, o.Quiet)
	case "setup":
		return runSetup(o)
	case "pre-update":
		return runPreUpdate()
	case "post-update":
		return runPostUpdate()
	default:
		fmt.Fprintf(os.Stderr, "Error: unsupported native schedule action %q\n", o.Action)
		return 1
	}
}

func helpText() string {
	return `Usage: millennium schedule <enable|disable|status|setup|config> [OPTIONS]

Native: status, enable/disable, setup wizard, pre/post-update (Unix/macOS),
--dry-run. Linux systemd prefers system units when privileged; otherwise user.
setup accepts --system / --user / --cron for the optional enable step.
config remains native via schedule config (dispatched separately).

Options:
  -c, --cron     Linux/macOS: force crontab (auto when systemd unavailable)
      --system   Linux: force systemd system units (requires root)
      --user     Linux: force systemd user units
  -d, --dry-run  Simulate without writing timer/cron/task state
  -q, --quiet
  -V, --version
  -h, --help
`
}

// StateDir returns the updater log parent directory.
func StateDir() string {
	if d := os.Getenv("MILLENNIUM_STATE_DIR"); d != "" {
		return d
	}
	if runtime.GOOS == "windows" {
		base := os.Getenv("LOCALAPPDATA")
		if base == "" {
			home, _ := os.UserHomeDir()
			base = filepath.Join(home, "AppData", "Local")
		}
		return filepath.Join(base, "millennium-helpers")
	}
	xdg := os.Getenv("XDG_STATE_HOME")
	if xdg == "" {
		home, _ := os.UserHomeDir()
		xdg = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(xdg, "millennium-helpers")
}

// LogPath returns updater.log path.
func LogPath() string {
	return filepath.Join(StateDir(), "updater.log")
}

// ResolvePackagedHelper prefers /usr/local/bin then /usr/bin then PATH.
func ResolvePackagedHelper(name string) string {
	for _, dir := range []string{"/usr/local/bin", "/usr/bin"} {
		p := filepath.Join(dir, name)
		if st, err := os.Stat(p); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return p
		}
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	return name
}

// isSchedulerCronLine matches both legacy long-name jobs and millennium <cmd> jobs.
func isSchedulerCronLine(line string) bool {
	return strings.Contains(line, "millennium-schedule") ||
		strings.Contains(line, "schedule pre-update") ||
		strings.Contains(line, "MILLENNIUM_SCHEDULER=1")
}

// UserSystemdDir returns ~/.config/systemd/user (honors XDG_CONFIG_HOME).
func UserSystemdDir() string {
	xdg := os.Getenv("XDG_CONFIG_HOME")
	if xdg == "" {
		home, _ := os.UserHomeDir()
		xdg = filepath.Join(home, ".config")
	}
	return filepath.Join(xdg, "systemd", "user")
}

const (
	ServiceName = "millennium-update.service"
	TimerName   = "millennium-update.timer"
	PlistLabel  = "com.millennium.update"
	WinTaskName = "MillenniumUpdate"
)

func ServicePath() string { return filepath.Join(UserSystemdDir(), ServiceName) }
func TimerPath() string   { return filepath.Join(UserSystemdDir(), TimerName) }

func PlistPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "LaunchAgents", PlistLabel+".plist")
}
