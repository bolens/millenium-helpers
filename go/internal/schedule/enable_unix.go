//go:build unix

package schedule

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func runEnable(channel string, useCron, dryRun, quiet bool, forceScope SystemdScope) int {
	upgrade := ResolvePackagedHelper("millennium-upgrade")
	if !dryRun {
		if _, err := os.Stat(upgrade); err != nil {
			fmt.Fprintf(os.Stderr, "Error: Installed updater script not found at %s.\n", upgrade)
			if runtime.GOOS == "darwin" {
				fmt.Fprintln(os.Stderr, "Please install the helper tools first via Homebrew.")
			} else {
				fmt.Fprintln(os.Stderr, "Please run the installer first: sudo ./install.sh")
			}
			return 1
		}
	}
	theme := ResolvePackagedHelper("millennium-theme")
	sched := ResolvePackagedHelper("millennium-schedule")

	if useCron {
		tu, _ := ResolveTargetUser()
		state := StateDirForUser(tu)
		return enableCron(channel, upgrade, theme, sched, state, dryRun, quiet)
	}
	if runtime.GOOS == "darwin" {
		tu, _ := ResolveTargetUser()
		state := StateDirForUser(tu)
		return enableLaunchd(channel, upgrade, theme, sched, state, dryRun, quiet)
	}
	return enableSystemd(channel, upgrade, theme, sched, dryRun, quiet, forceScope)
}

func runDisable(dryRun, quiet bool) int {
	code := 0
	if runtime.GOOS == "darwin" {
		code = disableLaunchd(dryRun, quiet)
	} else {
		code = disableSystemdAll(dryRun, quiet)
	}
	if c := disableCron(dryRun, quiet); c != 0 && code == 0 {
		code = c
	}
	return code
}

func enableSystemd(channel, upgrade, theme, sched string, dryRun, quiet bool, forceScope SystemdScope) int {
	scope, err := ResolveSystemdScope(forceScope)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	tu, err := ResolveTargetUser()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	state := StateDirForUser(tu)
	svcBody := BuildSystemdServiceUnit(channel, state, sched, upgrade, theme, scope, tu)
	timBody := BuildSystemdTimerUnit()

	var svcPath, timPath, svcDir string
	if scope == ScopeSystem {
		svcDir = SystemSystemdDir()
		svcPath = SystemServicePath()
		timPath = SystemTimerPath()
	} else {
		svcDir = UserSystemdDirFor(tu)
		svcPath = ServicePathFor(tu)
		timPath = TimerPathFor(tu)
	}

	if dryRun {
		fmt.Printf("[DRY RUN] Would use systemd %s scope\n", scope)
		fmt.Printf("[DRY RUN] Would write service: %s\n", svcPath)
		fmt.Printf("[DRY RUN] Would write timer: %s\n", timPath)
		if scope == ScopeSystem {
			fmt.Printf("[DRY RUN] Would disable conflicting user units (if any)\n")
			fmt.Println("[DRY RUN] Would run: systemctl daemon-reload")
			fmt.Printf("[DRY RUN] Would run: systemctl enable --now %s\n", TimerName)
		} else {
			fmt.Printf("[DRY RUN] Would disable conflicting system units (if privileged)\n")
			fmt.Println("[DRY RUN] Would run: systemctl --user daemon-reload")
			fmt.Printf("[DRY RUN] Would run: systemctl --user enable --now %s\n", TimerName)
		}
		fmt.Println("Dry run: Timer enablement simulated successfully.")
		return 0
	}

	// Prefer a single scope: clear the other before writing.
	if scope == ScopeSystem {
		_ = removeUserSystemdUnits(tu, false)
	} else {
		if CanUseSystemSystemd() {
			_ = removeSystemSystemdUnits(false)
		} else if _, err := os.Stat(SystemTimerPath()); err == nil {
			fmt.Fprintln(os.Stderr, "Warning: system timer units exist under /etc/systemd/system but this process cannot remove them.")
			fmt.Fprintln(os.Stderr, "Re-run with sudo to migrate fully to a user timer, or use: sudo millennium schedule enable --system")
		}
	}

	if err := os.MkdirAll(svcDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Creating systemd %s service file...\n", scope)
	if err := os.WriteFile(svcPath, []byte(svcBody), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: write service: %v\n", err)
		return 1
	}
	fmt.Printf("Creating systemd %s timer file...\n", scope)
	if err := os.WriteFile(timPath, []byte(timBody), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: write timer: %v\n", err)
		return 1
	}
	if scope == ScopeUser && os.Geteuid() == 0 && tu.Name != "root" {
		uid := parseUint(tu.UID)
		gid := parseUint(tu.GID)
		_ = os.Chown(svcDir, uid, gid)
		_ = os.Chown(svcPath, uid, gid)
		_ = os.Chown(timPath, uid, gid)
	}

	fmt.Printf("Reloading systemd %s daemon...\n", scope)
	_ = systemctlRun(scope, "daemon-reload")
	fmt.Printf("Enabling and starting %s...\n", TimerName)
	if err := systemctlRun(scope, "enable", "--now", TimerName); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: systemctl enable failed: %v\n", err)
	}
	if !quiet {
		fmt.Printf("Millennium auto-update %s timer (%s) has been enabled!\n", scope, channel)
		fmt.Println("It will run daily with a randomized delay of up to 1 hour.")
		warnSudoers(tu)
		if scope == ScopeUser {
			fmt.Printf("\nSystemd User Lingering (Optional):\nTo allow user timers when logged out: loginctl enable-linger %s\n", tu.Name)
		}
		fmt.Println("\nYou can check the status of the timer with: millennium schedule status")
	}
	return 0
}

func disableSystemdAll(dryRun, quiet bool) int {
	tu, err := ResolveTargetUser()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Println("Disabling Millennium update systemd timers (system and user scopes)...")
	if dryRun {
		fmt.Printf("[DRY RUN] Would stop/disable/remove system units under %s\n", SystemSystemdDir())
		fmt.Printf("[DRY RUN] Would stop/disable/remove user units under %s\n", UserSystemdDirFor(tu))
		fmt.Println("Dry run: Timer disablement simulated successfully.")
		return 0
	}
	had := false
	if CanUseSystemSystemd() || fileExists(SystemTimerPath()) || fileExists(SystemServicePath()) {
		if CanUseSystemSystemd() {
			_ = removeSystemSystemdUnits(true)
			had = true
		} else if fileExists(SystemTimerPath()) || fileExists(SystemServicePath()) {
			fmt.Fprintln(os.Stderr, "Warning: system units present but not removable without privileges; skipping system scope.")
		}
	}
	if err := removeUserSystemdUnits(tu, true); err == nil {
		had = true
	}
	if !quiet {
		if had {
			fmt.Println("Millennium auto-update systemd timers have been disabled and removed (where permitted).")
		} else {
			fmt.Println("No systemd timer units found to disable.")
		}
	}
	return 0
}

func removeSystemSystemdUnits(reload bool) error {
	_ = systemctlRun(ScopeSystem, "disable", "--now", TimerName)
	_ = systemctlRun(ScopeSystem, "stop", ServiceName)
	_ = os.Remove(SystemTimerPath())
	_ = os.Remove(SystemServicePath())
	if reload {
		_ = systemctlRun(ScopeSystem, "daemon-reload")
	}
	return nil
}

func removeUserSystemdUnits(tu TargetUser, reload bool) error {
	_ = systemctlRun(ScopeUser, "disable", "--now", TimerName)
	_ = systemctlRun(ScopeUser, "stop", ServiceName)
	_ = os.Remove(TimerPathFor(tu))
	_ = os.Remove(ServicePathFor(tu))
	// Also clear current-process user paths (legacy installs under root's HOME when sudo).
	_ = os.Remove(TimerPath())
	_ = os.Remove(ServicePath())
	if reload {
		_ = systemctlRun(ScopeUser, "daemon-reload")
	}
	return nil
}

func systemctlRun(scope SystemdScope, args ...string) error {
	var cmd *exec.Cmd
	if scope == ScopeUser {
		cmd = exec.Command("systemctl", append([]string{"--user"}, args...)...)
	} else {
		cmd = exec.Command("systemctl", args...)
	}
	return cmd.Run()
}

func parseUint(s string) int {
	var n int
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	return n
}

func enableLaunchd(channel, upgrade, theme, sched, state string, dryRun, quiet bool) int {
	plist := PlistPath()
	body := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>%s</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>mkdir -p '%s' && { MILLENNIUM_SCHEDULER=1 '%s' pre-update && '%s' --channel '%s' && '%s' update && MILLENNIUM_SCHEDULER=1 '%s' post-update; } >> '%s/updater.log' 2>&1</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
`, PlistLabel, state, sched, upgrade, channel, theme, sched, state)

	if dryRun {
		fmt.Printf("[DRY RUN] Would write LaunchAgent: %s\n", plist)
		fmt.Printf("[DRY RUN] Would load launchd agent: %s\n", plist)
		fmt.Println("Dry run: LaunchAgent enablement simulated successfully.")
		return 0
	}
	if err := os.MkdirAll(filepath.Dir(plist), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Println("Creating launchd plist file...")
	if err := os.WriteFile(plist, []byte(body), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Println("Loading launchd agent...")
	_ = exec.Command("launchctl", "unload", plist).Run()
	if err := exec.Command("launchctl", "load", plist).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: launchctl load failed: %v\n", err)
	}
	if !quiet {
		fmt.Printf("Millennium auto-update LaunchAgent (%s) has been enabled!\n", channel)
		fmt.Println("It will run daily at 2:00 AM.")
		fmt.Println("\nYou can check the status with: millennium schedule status")
	}
	return 0
}

func disableLaunchd(dryRun, quiet bool) int {
	plist := PlistPath()
	fmt.Println("Disabling and unloading Millennium update LaunchAgent...")
	if dryRun {
		fmt.Printf("[DRY RUN] Would unload and remove LaunchAgent: %s\n", plist)
		fmt.Println("Millennium auto-update LaunchAgent has been disabled and removed.")
		return 0
	}
	_ = exec.Command("launchctl", "unload", plist).Run()
	_ = os.Remove(plist)
	if !quiet {
		fmt.Println("Millennium auto-update LaunchAgent has been disabled and removed.")
	}
	return 0
}

func enableCron(channel, upgrade, theme, sched, state string, dryRun, quiet bool) int {
	cronCmd := fmt.Sprintf(
		`0 2 * * * sleep $(python3 -c 'import random; print(random.randint(0, 3600))') && mkdir -p %s && { MILLENNIUM_SCHEDULER=1 %s pre-update && /usr/bin/sudo -n %s --channel %s && %s update && MILLENNIUM_SCHEDULER=1 %s post-update; } >> %s/updater.log 2>&1`,
		shellQuote(state), shellQuote(sched), shellQuote(upgrade), channel, shellQuote(theme), shellQuote(sched), shellQuote(state),
	)
	fmt.Println("Configuring daily crontab job...")
	if dryRun {
		fmt.Printf("[DRY RUN] Would append to crontab:\n  %s\n", cronCmd)
		return 0
	}
	if _, err := exec.LookPath("crontab"); err != nil {
		fmt.Fprintln(os.Stderr, "Error: 'crontab' command not found. Please install a cron daemon (e.g. cronie, fcron).")
		return 1
	}
	existing, _ := exec.Command("crontab", "-l").CombinedOutput()
	var keep []string
	for _, line := range strings.Split(string(existing), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		if strings.Contains(line, "millennium-schedule") {
			continue
		}
		keep = append(keep, line)
	}
	keep = append(keep, cronCmd)
	cmd := exec.Command("crontab", "-")
	cmd.Stdin = strings.NewReader(strings.Join(keep, "\n") + "\n")
	if out, err := cmd.CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: crontab update failed: %v\n%s\n", err, out)
		return 1
	}
	if !quiet {
		fmt.Println("Millennium cron job successfully configured to run daily!")
	}
	return 0
}

func disableCron(dryRun, quiet bool) int {
	if _, err := exec.LookPath("crontab"); err != nil {
		return 0
	}
	fmt.Println("Removing crontab entry...")
	if dryRun {
		fmt.Println("[DRY RUN] Would remove millennium-schedule entries from crontab")
		return 0
	}
	existing, err := exec.Command("crontab", "-l").CombinedOutput()
	if err != nil {
		if !quiet {
			fmt.Println("No cron job found.")
		}
		return 0
	}
	var keep []string
	found := false
	for _, line := range strings.Split(string(existing), "\n") {
		if strings.Contains(line, "millennium-schedule") {
			found = true
			continue
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		keep = append(keep, line)
	}
	if !found {
		if !quiet {
			fmt.Println("No cron job found.")
		}
		return 0
	}
	if len(keep) == 0 {
		_ = exec.Command("crontab", "-r").Run()
	} else {
		cmd := exec.Command("crontab", "-")
		cmd.Stdin = strings.NewReader(strings.Join(keep, "\n") + "\n")
		_ = cmd.Run()
	}
	if !quiet {
		fmt.Println("Millennium cron job removed.")
	}
	return 0
}

func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func warnSudoers(tu TargetUser) {
	var cmd *exec.Cmd
	if os.Geteuid() == 0 && tu.Name != "" && tu.Name != "root" {
		cmd = exec.Command("sudo", "-U", tu.Name, "-n", "-l")
	} else {
		cmd = exec.Command("sudo", "-n", "-l")
	}
	out, err := cmd.CombinedOutput()
	text := string(out)
	if err != nil || (!strings.Contains(text, "millennium-upgrade") && !strings.Contains(text, "NOPASSWD: ALL") && !strings.Contains(text, "NOPASSWD:ALL")) {
		fmt.Println("\nWarning: Passwordless sudo for the updater script could not be verified.")
		fmt.Println("Make sure you have run the installer first: sudo ./install.sh")
		fmt.Println("This configuration is required for the background timer to run successfully.")
		return
	}
	fmt.Println("\nSudo Passwordless Configuration:")
	fmt.Println("The installer has automatically configured the required passwordless sudo rule at:")
	fmt.Println("  /etc/sudoers.d/millennium-helpers")
}
