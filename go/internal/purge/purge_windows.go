//go:build windows

package purge

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/schedule"
	"github.com/bolens/millenium-helpers/internal/steam"
	"github.com/bolens/millenium-helpers/internal/theme"
)

func planWindows() []Action {
	var out []Action
	steam := theme.FindSteamDir()
	if steam != "" {
		for _, item := range []struct {
			rel  string
			kind string
			det  string
		}{
			{"millennium", "millennium_dir", "remove tree"},
			{"wsock32.dll", "wsock32", "remove bootstrap DLL"},
			{"millennium_backups", "backups", "remove backup tree"},
		} {
			p := filepath.Join(steam, item.rel)
			if pathExists(p) {
				out = append(out, Action{Path: p, Kind: item.kind, Detail: item.det})
			}
		}
	}
	if cfg := config.Dir(); cfg != "" && pathExists(cfg) {
		out = append(out, Action{Path: cfg, Kind: "config_dir", Detail: "remove helper config"})
	}
	if windowsTaskPresent() {
		out = append(out, Action{
			Path:   schedule.WinTaskName,
			Kind:   "scheduled_task",
			Detail: "unregister Task Scheduler task",
		})
	}
	return out
}

func applyWindowsExtra(a Action) error {
	switch a.Kind {
	case "scheduled_task":
		fmt.Printf("Unregistering scheduled task: %s\n", a.Path)
		cmd := exec.Command("schtasks", "/Delete", "/TN", a.Path, "/F")
		if out, err := cmd.CombinedOutput(); err != nil {
			// PowerShell fallback (admin may still be required)
			ps := fmt.Sprintf(`
$ErrorActionPreference='Stop'
$t = Get-ScheduledTask -TaskName %s -ErrorAction SilentlyContinue
if ($null -ne $t) { Unregister-ScheduledTask -TaskName %s -Confirm:$false }
`, psQuote(a.Path), psQuote(a.Path))
			psCmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", ps)
			if out2, err2 := psCmd.CombinedOutput(); err2 != nil {
				return fmt.Errorf("unregister task %s: %v (%s; ps: %s)", a.Path, err, strings.TrimSpace(string(out)), strings.TrimSpace(string(out2)))
			}
		}
		return nil
	default:
		return nil // fall through to generic RemoveAll
	}
}

func ensureSteamClosedForPurge(yes bool) (relaunch bool, err error) {
	if !steam.IsSteamRunning() {
		return false, nil
	}
	if err := steam.ConfirmClose(yes); err != nil {
		return false, err
	}
	return true, nil
}

func relaunchSteamBestEffort() {
	steam.RelaunchBestEffort()
}

func windowsTaskPresent() bool {
	out, err := exec.Command("schtasks", "/Query", "/TN", schedule.WinTaskName).CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), schedule.WinTaskName)
}

func pathExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func psQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}
