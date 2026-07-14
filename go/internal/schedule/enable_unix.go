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

func runEnable(channel string, useCron, dryRun, quiet bool) int {
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
	state := StateDir()

	if useCron {
		return enableCron(channel, upgrade, theme, sched, state, dryRun, quiet)
	}
	if runtime.GOOS == "darwin" {
		return enableLaunchd(channel, upgrade, theme, sched, state, dryRun, quiet)
	}
	return enableSystemd(channel, upgrade, theme, sched, state, dryRun, quiet)
}

func runDisable(dryRun, quiet bool) int {
	code := 0
	if runtime.GOOS == "darwin" {
		code = disableLaunchd(dryRun, quiet)
	} else {
		code = disableSystemd(dryRun, quiet)
	}
	if c := disableCron(dryRun, quiet); c != 0 && code == 0 {
		code = c
	}
	return code
}

func enableSystemd(channel, upgrade, theme, sched, state string, dryRun, quiet bool) int {
	svcDir := UserSystemdDir()
	svc := ServicePath()
	tim := TimerPath()

	svcBody := fmt.Sprintf(`[Unit]
Description=Auto-update Millennium client (%s) and themes
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p "%s" && { MILLENNIUM_SCHEDULER=1 "%s" pre-update && /usr/bin/sudo -n "%s" --channel "%s" --quiet && "%s" update --quiet && MILLENNIUM_SCHEDULER=1 "%s" post-update; } >> "%s/updater.log" 2>&1'
`, channel, state, sched, upgrade, channel, theme, sched, state)

	timBody := `[Unit]
Description=Trigger Millennium auto-update daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
`

	if dryRun {
		fmt.Printf("[DRY RUN] Would write service: %s\n", svc)
		fmt.Printf("[DRY RUN] Would write timer: %s\n", tim)
		fmt.Println("[DRY RUN] Would run: systemctl --user daemon-reload")
		fmt.Printf("[DRY RUN] Would run: systemctl --user enable --now %s\n", TimerName)
		fmt.Println("Dry run: Timer enablement simulated successfully.")
		return 0
	}

	if err := os.MkdirAll(svcDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Println("Creating systemd user service file...")
	if err := os.WriteFile(svc, []byte(svcBody), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: write service: %v\n", err)
		return 1
	}
	fmt.Println("Creating systemd user timer file...")
	if err := os.WriteFile(tim, []byte(timBody), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: write timer: %v\n", err)
		return 1
	}
	fmt.Println("Reloading systemd user daemon...")
	_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	fmt.Printf("Enabling and starting %s...\n", TimerName)
	if err := exec.Command("systemctl", "--user", "enable", "--now", TimerName).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: systemctl enable failed: %v\n", err)
	}
	if !quiet {
		fmt.Printf("Millennium auto-update user timer (%s) has been enabled!\n", channel)
		fmt.Println("It will run daily with a randomized delay of up to 1 hour.")
		warnSudoers()
		fmt.Println("\nYou can check the status of the timer with: millennium schedule status")
	}
	return 0
}

func disableSystemd(dryRun, quiet bool) int {
	fmt.Println("Disabling and stopping Millennium update user timer and service...")
	if dryRun {
		fmt.Printf("[DRY RUN] Would stop and disable timer: %s\n", TimerName)
		fmt.Printf("[DRY RUN] Would stop service: %s\n", ServiceName)
		fmt.Printf("[DRY RUN] Would remove: %s\n", TimerPath())
		fmt.Printf("[DRY RUN] Would remove: %s\n", ServicePath())
		fmt.Println("[DRY RUN] Would run: systemctl --user daemon-reload")
		fmt.Println("Dry run: Timer disablement simulated successfully.")
		return 0
	}
	_ = exec.Command("systemctl", "--user", "disable", "--now", TimerName).Run()
	_ = exec.Command("systemctl", "--user", "stop", ServiceName).Run()
	_ = os.Remove(TimerPath())
	_ = os.Remove(ServicePath())
	_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	if !quiet {
		fmt.Println("Millennium auto-update user timer and service have been disabled and removed.")
	}
	return 0
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

func warnSudoers() {
	out, err := exec.Command("sudo", "-n", "-l").CombinedOutput()
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
