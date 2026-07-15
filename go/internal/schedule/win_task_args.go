package schedule

import (
	"fmt"
	"strings"
)

// psSingle quotes a PowerShell single-quoted string (escape ' as ”).
func psSingle(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// escSQ escapes a value for embedding inside a PowerShell single-quoted literal.
func escSQ(s string) string {
	return strings.ReplaceAll(s, "'", "''")
}

// buildEnablePowerShell builds the scheduled action argument and Register-ScheduledTask script.
// upgrade/theme are paths to millennium.exe; commands are invoked as Go dispatcher subcommands.
func buildEnablePowerShell(channel, configDir, upgrade, theme, logPath string, delayMin int) (taskArg, registerScript string) {
	inner := strings.Join([]string{
		fmt.Sprintf("New-Item -ItemType Directory -Force -Path '%s' | Out-Null", escSQ(configDir)),
		fmt.Sprintf("& '%s' upgrade --channel '%s' --yes --quiet *>> '%s'", escSQ(upgrade), escSQ(channel), escSQ(logPath)),
		fmt.Sprintf("if (Test-Path -LiteralPath '%s') { & '%s' theme update --quiet *>> '%s' }", escSQ(theme), escSQ(theme), escSQ(logPath)),
	}, "; ")
	// Escape " so a hostile path cannot break out of -Command "..."
	cmdBody := strings.ReplaceAll(inner, `"`, "`\"")
	taskArg = fmt.Sprintf(`-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "%s"`, cmdBody)
	registerScript = fmt.Sprintf(`
$ErrorActionPreference = 'Stop'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument %s
$trigger = New-ScheduledTaskTrigger -Daily -At '2:00AM'
$trigger.RandomDelay = New-TimeSpan -Minutes %d
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName %s -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
`, psSingle(taskArg), delayMin, psSingle(WinTaskName))
	return taskArg, registerScript
}
