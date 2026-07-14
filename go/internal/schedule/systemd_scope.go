package schedule

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
)

// SystemdScope selects Linux systemd unit installation scope.
type SystemdScope string

const (
	ScopeAuto   SystemdScope = ""
	ScopeSystem SystemdScope = "system"
	ScopeUser   SystemdScope = "user"
)

// TargetUser is the Linux account timers should run as (SUDO_USER when elevated).
type TargetUser struct {
	Name  string
	Home  string
	UID   string
	GID   string
	Group string
}

// SystemSystemdDir returns /etc/systemd/system (overridable for tests).
func SystemSystemdDir() string {
	if d := os.Getenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR"); d != "" {
		return d
	}
	return "/etc/systemd/system"
}

func SystemServicePath() string { return filepath.Join(SystemSystemdDir(), ServiceName) }
func SystemTimerPath() string   { return filepath.Join(SystemSystemdDir(), TimerName) }

// SystemdAvailable is true when a systemd system manager appears present.
func SystemdAvailable() bool {
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		return false
	}
	st, err := os.Stat("/run/systemd/system")
	return err == nil && st.IsDir()
}

// CanUseSystemSystemd reports whether this process can install system units.
func CanUseSystemSystemd() bool {
	if os.Getenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR") == "" && !SystemdAvailable() {
		return false
	}
	dir := SystemSystemdDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false
	}
	f, err := os.CreateTemp(dir, ".millennium-writetest-*")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name)
	return true
}

// ResolveSystemdScope applies auto preference: system when possible, else user.
func ResolveSystemdScope(force SystemdScope) (SystemdScope, error) {
	switch force {
	case ScopeSystem:
		if !CanUseSystemSystemd() {
			return "", fmt.Errorf("Error: --system requires write access to %s and a systemd system manager (try: sudo millennium schedule enable --system).", SystemSystemdDir())
		}
		return ScopeSystem, nil
	case ScopeUser:
		return ScopeUser, nil
	case ScopeAuto:
		if CanUseSystemSystemd() {
			return ScopeSystem, nil
		}
		return ScopeUser, nil
	default:
		return "", fmt.Errorf("Error: invalid systemd scope %q", force)
	}
}

// ResolveTargetUser returns the user account for User= / state paths.
func ResolveTargetUser() (TargetUser, error) {
	name := os.Getenv("SUDO_USER")
	if name == "" || effectiveUID() != 0 {
		u, err := user.Current()
		if err != nil {
			return TargetUser{}, err
		}
		return TargetUser{Name: u.Username, Home: u.HomeDir, UID: u.Uid, GID: u.Gid, Group: u.Username}, nil
	}
	u, err := user.Lookup(name)
	if err != nil {
		return TargetUser{}, fmt.Errorf("Error: cannot resolve SUDO_USER %q: %w", name, err)
	}
	group := name
	if g, err := user.LookupGroupId(u.Gid); err == nil {
		group = g.Name
	}
	return TargetUser{Name: u.Username, Home: u.HomeDir, UID: u.Uid, GID: u.Gid, Group: group}, nil
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// StateDirForUser returns XDG state dir for the target account (not root's when sudo).
func StateDirForUser(tu TargetUser) string {
	if d := os.Getenv("MILLENNIUM_STATE_DIR"); d != "" {
		return d
	}
	return filepath.Join(tu.Home, ".local", "state", "millennium-helpers")
}

// UserSystemdDirFor returns ~/.config/systemd/user for tu.
func UserSystemdDirFor(tu TargetUser) string {
	return filepath.Join(tu.Home, ".config", "systemd", "user")
}

func ServicePathFor(tu TargetUser) string {
	return filepath.Join(UserSystemdDirFor(tu), ServiceName)
}

func TimerPathFor(tu TargetUser) string {
	return filepath.Join(UserSystemdDirFor(tu), TimerName)
}

// BuildSystemdServiceUnit renders the oneshot service unit body.
func BuildSystemdServiceUnit(channel, state, sched, upgrade, theme string, scope SystemdScope, tu TargetUser) string {
	exec := fmt.Sprintf(
		`/bin/bash -c 'mkdir -p "%s" && { MILLENNIUM_SCHEDULER=1 "%s" pre-update && /usr/bin/sudo -n "%s" --channel "%s" --quiet && "%s" update --quiet && MILLENNIUM_SCHEDULER=1 "%s" post-update; } >> "%s/updater.log" 2>&1'`,
		state, sched, upgrade, channel, theme, sched, state,
	)
	var b string
	b += "[Unit]\n"
	b += fmt.Sprintf("Description=Auto-update Millennium client (%s) and themes\n", channel)
	b += "After=network-online.target\n"
	b += "Wants=network-online.target\n\n"
	b += "[Service]\n"
	b += "Type=oneshot\n"
	if scope == ScopeSystem && tu.Name != "" && tu.Name != "root" {
		b += fmt.Sprintf("User=%s\n", tu.Name)
		if tu.Group != "" {
			b += fmt.Sprintf("Group=%s\n", tu.Group)
		}
		if tu.Home != "" {
			b += fmt.Sprintf("Environment=HOME=%s\n", tu.Home)
		}
	}
	b += fmt.Sprintf("ExecStart=%s\n", exec)
	return b
}

// BuildSystemdTimerUnit renders the daily timer unit body.
func BuildSystemdTimerUnit() string {
	return `[Unit]
Description=Trigger Millennium auto-update daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
`
}
