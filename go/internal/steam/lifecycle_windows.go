//go:build windows

package steam

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type winRelaunchState struct {
	SteamRunning bool   `json:"SteamRunning"`
	Executable   string `json:"Executable"`
	Arguments    string `json:"Arguments"`
}

// RelaunchStateFileWindows returns %LOCALAPPDATA%\millennium-helpers\relaunch_state.json.
func RelaunchStateFileWindows() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, "AppData", "Local")
	}
	return filepath.Join(base, "millennium-helpers", "relaunch_state.json")
}

func IsSteamRunning() bool {
	out, err := exec.Command("tasklist", "/FI", "IMAGENAME eq steam.exe").CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), "steam.exe")
}

func IsGameRunning() bool {
	ps := `
$ErrorActionPreference='SilentlyContinue'
$steam = Get-Process steam -ErrorAction SilentlyContinue
if (-not $steam) { exit 1 }
$games = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -ne 'steam.exe' -and $_.Name -ne 'steamwebhelper.exe' -and $_.Name -ne 'steamservice.exe' -and
  $_.ExecutablePath -and $_.ExecutablePath -like '*\steamapps\common\*'
}
if ($games) { exit 0 } else { exit 1 }
`
	return exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps).Run() == nil
}

// CaptureEnv writes Windows relaunch_state.json (username/home unused; kept for API parity).
func CaptureEnv(username, home string) error {
	_, _ = username, home
	stateFile := RelaunchStateFileWindows()
	stateDir := filepath.Dir(stateFile)

	var steamArgs, exePath string
	steamRunning := IsSteamRunning()
	if steamRunning {
		ps := `
$ErrorActionPreference='SilentlyContinue'
$p = Get-Process -Name steam -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $p) { '' ; '' ; exit 0 }
$path = $p.Path
$wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction SilentlyContinue
$args = ''
if ($wmi -and $wmi.CommandLine) {
  $cmd = $wmi.CommandLine.Trim()
  if ($cmd.StartsWith('"')) {
    $end = $cmd.IndexOf('"', 1)
    if ($end -gt 0) { $args = $cmd.Substring($end + 1).Trim() }
  } else {
    $sp = $cmd.IndexOf(' ')
    if ($sp -gt 0) { $args = $cmd.Substring($sp + 1).Trim() }
  }
}
Write-Output $path
Write-Output $args
`
		out, err := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps).CombinedOutput()
		if err == nil {
			lines := strings.Split(strings.ReplaceAll(string(out), "\r\n", "\n"), "\n")
			if len(lines) >= 1 {
				exePath = strings.TrimSpace(lines[0])
			}
			if len(lines) >= 2 {
				steamArgs = strings.TrimSpace(lines[1])
			}
		}
	}

	state := winRelaunchState{
		SteamRunning: steamRunning,
		Executable:   exePath,
		Arguments:    steamArgs,
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(stateFile, b, 0o600)
}

func CloseGracefully(username, home string) error {
	_, _ = username, home
	if !IsSteamRunning() {
		return nil
	}
	fmt.Println("Closing Steam gracefully...")
	steam := FindDir()
	exe := filepath.Join(steam, "steam.exe")
	if steam != "" {
		if st, err := os.Stat(exe); err == nil && !st.IsDir() {
			_ = exec.Command(exe, "-shutdown").Run()
		} else {
			_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
		}
	} else {
		_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
	}
	deadline := time.Now().Add(10 * time.Second)
	for IsSteamRunning() && time.Now().Before(deadline) {
		time.Sleep(time.Second)
	}
	if IsSteamRunning() {
		_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
	}
	fmt.Println("Steam closed successfully.")
	return nil
}

func RelaunchFromState(username, home string) (bool, error) {
	_, _ = username, home
	stateFile := RelaunchStateFileWindows()
	b, err := os.ReadFile(stateFile)
	if err != nil {
		return false, nil
	}
	defer func() { _ = os.Remove(stateFile) }()

	var state winRelaunchState
	if err := json.Unmarshal(b, &state); err != nil {
		return false, fmt.Errorf("failed to parse relaunch state: %w", err)
	}
	if !state.SteamRunning || state.Executable == "" {
		return false, nil
	}
	fmt.Printf("Relaunching Steam client: %s %s\n", state.Executable, state.Arguments)
	if testSuite() {
		fmt.Println("[TEST] Bypassing real Steam relaunch in test suite.")
		return true, nil
	}
	cmd := exec.Command(state.Executable)
	if state.Arguments != "" {
		cmd = exec.Command(state.Executable, strings.Fields(state.Arguments)...)
	}
	return true, cmd.Start()
}

// RelaunchBestEffort starts steam.exe from FindDir when present.
func RelaunchBestEffort() {
	steam := FindDir()
	if steam == "" {
		return
	}
	_ = exec.Command(filepath.Join(steam, "steam.exe")).Start()
}
