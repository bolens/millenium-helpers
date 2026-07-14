package schedule

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/bolens/millenium-helpers/internal/config"
)

func TestNeedsLegacySetupNative(t *testing.T) {
	if NeedsLegacy(Options{Action: "setup"}) {
		t.Fatal("setup should be native")
	}
	if NeedsLegacy(Options{Action: "config"}) {
		t.Fatal("config should be native")
	}
}

func TestSetupWizardDryRunPreserveDefaults(t *testing.T) {
	home := t.TempDir()
	cfgDir := filepath.Join(home, ".config", "millennium-helpers")
	_ = os.MkdirAll(cfgDir, 0o700)
	cfgPath := filepath.Join(cfgDir, "config.json")
	body := `{
  "update_channel": "beta",
  "github_token": "token_existing_pat",
  "backup_limit": 7,
  "backup_max_age_days": 14
}
`
	if err := os.WriteFile(cfgPath, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("LOCALAPPDATA", filepath.Join(home, "AppData", "Local"))
	t.Setenv("MILLENNIUM_CONFIG_DIR", cfgDir)
	t.Setenv("MILLENNIUM_CONFIG_FILE", "")
	t.Setenv("FORCE_WIZARD", "true")
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))

	// Explicit "n" for enable — host may already have a real timer (Configured=true).
	answers := []string{"", "n", ""} // channel default (beta), no enable, keep PAT
	idx := 0
	readPromptLine = func(prompt string) (string, error) {
		if idx >= len(answers) {
			return "n", nil
		}
		a := answers[idx]
		idx++
		return a, nil
	}
	readPromptSecret = readPromptLine
	t.Cleanup(func() {
		readPromptLine = defaultReadLine
		readPromptSecret = defaultReadSecret
	})

	// Capture stdout loosely via verifying return + config untouched.
	code := runSetup(Options{Action: "setup", DryRun: true})
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
	data, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if config.Get(data, "update_channel") != "beta" {
		t.Fatalf("dry-run must not rewrite channel: %v", data)
	}
	if config.Get(data, "backup_limit") != "7" {
		t.Fatalf("backup_limit touched: %v", data)
	}
	_ = runtime.GOOS
}

func TestSetupWizardLivePreserveBackupKeys(t *testing.T) {
	home := t.TempDir()
	cfgDir := filepath.Join(home, ".config", "millennium-helpers")
	_ = os.MkdirAll(cfgDir, 0o700)
	cfgPath := filepath.Join(cfgDir, "config.json")
	body := `{
  "update_channel": "beta",
  "github_token": "token_existing_pat",
  "backup_limit": 7,
  "backup_max_age_days": 14
}
`
	if err := os.WriteFile(cfgPath, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("LOCALAPPDATA", filepath.Join(home, "AppData", "Local"))
	t.Setenv("MILLENNIUM_CONFIG_DIR", cfgDir)
	t.Setenv("MILLENNIUM_CONFIG_FILE", "")
	t.Setenv("FORCE_WIZARD", "true")
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))

	answers := []string{"", "n", ""} // keep beta, don't enable, keep token
	idx := 0
	readPromptLine = func(string) (string, error) {
		if idx >= len(answers) {
			return "n", nil
		}
		a := answers[idx]
		idx++
		return a, nil
	}
	readPromptSecret = readPromptLine
	t.Cleanup(func() {
		readPromptLine = defaultReadLine
		readPromptSecret = defaultReadSecret
	})

	code := runSetup(Options{Action: "setup"})
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
	data, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if config.Get(data, "update_channel") != "beta" {
		t.Fatalf("channel=%q", config.Get(data, "update_channel"))
	}
	if config.Get(data, "github_token") != "token_existing_pat" {
		t.Fatalf("token=%q", config.Get(data, "github_token"))
	}
	if config.Get(data, "backup_limit") != "7" || config.Get(data, "backup_max_age_days") != "14" {
		t.Fatalf("backup keys not preserved: %v", data)
	}
}

func TestSetupRejectsNonInteractive(t *testing.T) {
	t.Setenv("FORCE_WIZARD", "")
	stdinInteractive = func() bool { return false }
	t.Cleanup(func() { stdinInteractive = defaultStdinInteractive })
	if code := runSetup(Options{Action: "setup"}); code != 1 {
		t.Fatalf("code=%d", code)
	}
}

func TestPromptChannelDefaults(t *testing.T) {
	answers := []string{""}
	idx := 0
	readPromptLine = func(string) (string, error) {
		a := answers[idx]
		idx++
		return a, nil
	}
	t.Cleanup(func() { readPromptLine = defaultReadLine })
	ch, err := promptChannel(config.Data{"update_channel": "main"})
	if err != nil || ch != "main" {
		t.Fatalf("ch=%q err=%v", ch, err)
	}
	_ = strings.Contains
}
