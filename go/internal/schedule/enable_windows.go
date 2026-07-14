//go:build windows

package schedule

import (
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/legacy"
)

// Test seams
var (
	windowsAdminCheck = isWindowsAdmin
	windowsPowerShell = runPowerShell
)

func runEnable(channel string, useCron, dryRun, quiet bool, _ SystemdScope) int {
	_ = useCron
	if dryRun {
		fmt.Printf("[DRY RUN] Would register Task Scheduler task %s (channel %s)\n", WinTaskName, channel)
		fmt.Println("Dry run: Scheduled task enablement simulated successfully.")
		return 0
	}
	if !windowsAdminCheck() {
		fmt.Fprintln(os.Stderr, "Error: Administrator privileges are required to configure Scheduled Tasks.")
		return 1
	}
	upgradeScript, themeScript, err := resolveWindowsHelpers()
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	configDir := config.Dir()
	logPath := LogPath()
	delayMin := rand.Intn(60)
	fmt.Printf("Configuring Windows Task Scheduler task '%s' (%s channel)...\n", WinTaskName, channel)

	taskArg, psScript := buildEnablePowerShell(channel, configDir, upgradeScript, themeScript, logPath, delayMin)
	if !quiet {
		fmt.Printf("Task command: powershell.exe %s\n", taskArg)
	}
	if out, err := windowsPowerShell(psScript); err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to register scheduled task: %v\n%s\n", err, out)
		return 1
	}
	if !quiet {
		fmt.Println("Millennium auto-update scheduled task has been enabled!")
		fmt.Println("It will run daily with a randomized delay of up to 1 hour.")
		fmt.Printf("Logs append to: %s\n", logPath)
	}
	return 0
}

func runDisable(dryRun, quiet bool) int {
	if dryRun {
		fmt.Printf("[DRY RUN] Would unregister Task Scheduler task %s\n", WinTaskName)
		fmt.Println("Dry run: Scheduled task disablement simulated successfully.")
		return 0
	}
	if !windowsAdminCheck() {
		fmt.Fprintln(os.Stderr, "Error: Administrator privileges are required to remove Scheduled Tasks.")
		return 1
	}
	fmt.Printf("Disabling and removing scheduled task '%s'...\n", WinTaskName)
	ps := fmt.Sprintf(`
$ErrorActionPreference = 'Stop'
$task = Get-ScheduledTask -TaskName %s -ErrorAction SilentlyContinue
if ($null -ne $task) {
  Unregister-ScheduledTask -TaskName %s -Confirm:$false
  Write-Output 'removed'
} else {
  Write-Output 'missing'
}
`, psSingle(WinTaskName), psSingle(WinTaskName))
	out, err := windowsPowerShell(ps)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to unregister scheduled task: %v\n%s\n", err, out)
		return 1
	}
	if !quiet {
		if strings.Contains(out, "removed") {
			fmt.Printf("Scheduled task '%s' has been removed.\n", WinTaskName)
		} else {
			fmt.Println("No scheduled task found to disable.")
		}
	}
	return 0
}

func resolveWindowsHelpers() (upgrade, theme string, err error) {
	dir := legacy.ScriptDir()
	if dir == "" {
		return "", "", fmt.Errorf("Error: could not locate Windows helper scripts directory (set MILLENNIUM_SCRIPTS_DIR).")
	}
	upgrade = filepath.Join(dir, "millennium-upgrade.ps1")
	theme = filepath.Join(dir, "millennium-theme.ps1")
	if _, e := os.Stat(upgrade); e != nil {
		return "", "", fmt.Errorf("Error: Millennium upgrade script not found at %s", upgrade)
	}
	return upgrade, theme, nil
}

func isWindowsAdmin() bool {
	cmd := exec.Command("net", "session")
	return cmd.Run() == nil
}

func runPowerShell(script string) (string, error) {
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
	out, err := cmd.CombinedOutput()
	return string(out), err
}
