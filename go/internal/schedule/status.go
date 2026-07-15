package schedule

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
)

// Status is a cross-platform scheduler snapshot.
type Status struct {
	Configured bool
	Channel    string
	Lines      []string // human status sections already formatted (without summary)
}

// CollectStatus gathers timer/task/cron presence without mutating state.
func CollectStatus() Status {
	st := Status{Channel: ResolveChannel("")}
	switch runtime.GOOS {
	case "darwin":
		collectDarwin(&st)
	case "windows":
		collectWindows(&st)
	default:
		collectLinux(&st)
	}
	return st
}

func collectLinux(st *Status) {
	tu, err := ResolveTargetUser()
	if err != nil {
		tu = TargetUser{}
	}

	st.Lines = append(st.Lines, "=== Millennium System Update Timer Status ===")
	sysTim := SystemTimerPath()
	sysSvc := SystemServicePath()
	if fileExists(sysTim) {
		st.Configured = true
		st.Lines = append(st.Lines, fmt.Sprintf("Timer unit present: %s", sysTim))
		if out := systemctlStatus(ScopeSystem, TimerName); out != "" {
			st.Lines = append(st.Lines, out)
		}
	} else {
		st.Lines = append(st.Lines, "System timer is not installed/configured.")
	}
	st.Lines = append(st.Lines, "", "=== Millennium System Update Service Status ===")
	if fileExists(sysSvc) {
		st.Configured = true
		st.Lines = append(st.Lines, fmt.Sprintf("Service unit present: %s", sysSvc))
		if ch := channelFromServiceFile(sysSvc); ch != "" {
			st.Channel = ch
		}
		if out := systemctlStatus(ScopeSystem, ServiceName); out != "" {
			st.Lines = append(st.Lines, out)
		}
	} else {
		st.Lines = append(st.Lines, "System service is not installed/configured.")
	}

	userTim := TimerPathFor(tu)
	userSvc := ServicePathFor(tu)
	// Also probe process user's path (legacy sudo installs).
	if !fileExists(userTim) {
		userTim = TimerPath()
	}
	if !fileExists(userSvc) {
		userSvc = ServicePath()
	}

	st.Lines = append(st.Lines, "", "=== Millennium User Update Timer Status ===")
	if fileExists(userTim) {
		st.Configured = true
		st.Lines = append(st.Lines, fmt.Sprintf("Timer unit present: %s", userTim))
		if out := systemctlStatus(ScopeUser, TimerName); out != "" {
			st.Lines = append(st.Lines, out)
		}
	} else {
		st.Lines = append(st.Lines, "User timer is not installed/configured.")
	}
	st.Lines = append(st.Lines, "", "=== Millennium User Update Service Status ===")
	if fileExists(userSvc) {
		st.Configured = true
		st.Lines = append(st.Lines, fmt.Sprintf("Service unit present: %s", userSvc))
		if ch := channelFromServiceFile(userSvc); ch != "" {
			st.Channel = ch
		}
		if out := systemctlStatus(ScopeUser, ServiceName); out != "" {
			st.Lines = append(st.Lines, out)
		}
	} else {
		st.Lines = append(st.Lines, "User service is not installed/configured.")
	}

	appendCronStatus(st)
}

func collectDarwin(st *Status) {
	st.Lines = append(st.Lines, "=== Millennium LaunchAgent Status ===")
	plist := PlistPath()
	if _, err := os.Stat(plist); err == nil {
		st.Configured = true
		st.Lines = append(st.Lines, "LaunchAgent plist file exists: "+plist)
		if out, err := exec.Command("launchctl", "list").CombinedOutput(); err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if strings.Contains(line, PlistLabel) {
					st.Lines = append(st.Lines, strings.TrimSpace(line))
					break
				}
			}
		} else {
			st.Lines = append(st.Lines, "LaunchAgent is registered but currently idle.")
		}
	} else {
		st.Lines = append(st.Lines, "LaunchAgent is not installed/configured.")
	}
	appendCronStatus(st)
}

func collectWindows(st *Status) {
	st.Lines = append(st.Lines, "=== Millennium Scheduled Task Status ===")
	out, err := exec.Command("schtasks", "/Query", "/TN", WinTaskName, "/FO", "LIST", "/V").CombinedOutput()
	text := string(out)
	if err != nil || !strings.Contains(text, WinTaskName) {
		st.Lines = append(st.Lines, "  Scheduled task is not registered.")
		return
	}
	st.Configured = true
	st.Lines = append(st.Lines, "  Task Name   : "+WinTaskName)
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Status:") || strings.HasPrefix(line, "Task To Run:") ||
			strings.HasPrefix(line, "Task Name:") {
			st.Lines = append(st.Lines, "  "+line)
		}
		if m := regexp.MustCompile(`(?i)(?:-Channel|--channel)\s+(\S+)`).FindStringSubmatch(line); len(m) == 2 {
			st.Channel = m[1]
		}
	}
}

func appendCronStatus(st *Status) {
	if _, err := exec.LookPath("crontab"); err != nil {
		return
	}
	st.Lines = append(st.Lines, "", "=== Millennium Crontab Status ===")
	out, err := exec.Command("crontab", "-l").CombinedOutput()
	if err != nil {
		st.Lines = append(st.Lines, "No crontab entry configured.")
		return
	}
	found := false
	for _, line := range strings.Split(string(out), "\n") {
		if isSchedulerCronLine(line) {
			st.Configured = true
			st.Lines = append(st.Lines, line)
			found = true
		}
	}
	if !found {
		st.Lines = append(st.Lines, "No crontab entry configured.")
	}
}

func systemctlStatus(scope SystemdScope, unit string) string {
	var cmd *exec.Cmd
	if scope == ScopeUser {
		cmd = exec.Command("systemctl", "--user", "status", unit)
	} else {
		cmd = exec.Command("systemctl", "status", unit)
	}
	out, err := cmd.CombinedOutput()
	if err != nil && len(out) == 0 {
		return ""
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) > 12 {
		lines = lines[:12]
	}
	return strings.Join(lines, "\n")
}

var channelFlagRE = regexp.MustCompile(`--channel[[:space:]]+([a-z]+)`)

func channelFromServiceFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	m := channelFlagRE.FindSubmatch(b)
	if len(m) == 2 {
		return string(m[1])
	}
	return ""
}

// FormatStatus renders CollectStatus output including summary CTAs.
func FormatStatus(st Status) string {
	var b strings.Builder
	for i, line := range st.Lines {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(line)
	}
	b.WriteByte('\n')
	if !st.Configured {
		b.WriteString("\nScheduler disabled. Enable with: millennium schedule enable [stable|beta|main]\n")
		return b.String()
	}
	b.WriteString("\n=== Scheduler summary ===\n")
	fmt.Fprintf(&b, "  Channel     : %s\n", st.Channel)
	log := LogPath()
	if _, err := os.Stat(log); err == nil {
		fmt.Fprintf(&b, "  Last log    : %s\n", log)
		b.WriteString("  View logs   : millennium diag logs\n")
	} else {
		b.WriteString("  Last log    : (none yet — runs after the first scheduled update)\n")
	}
	b.WriteString("  Disable     : millennium schedule disable\n")
	return b.String()
}
