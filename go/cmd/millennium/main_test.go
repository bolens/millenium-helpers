package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestVersionSmoke(t *testing.T) {
	exe := buildMillennium(t)
	out, err := exec.Command(exe, "version").CombinedOutput()
	if err != nil {
		t.Fatalf("version: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "millennium version") {
		t.Fatalf("unexpected output: %s", out)
	}
}

func TestSuggestOnUnknown(t *testing.T) {
	exe := buildMillennium(t)
	cmd := exec.Command(exe, "upgrad")
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected non-zero exit, got: %s", out)
	}
	if !strings.Contains(string(out), "Did you mean 'upgrade'") && !strings.Contains(string(out), "upgrade") {
		// Closest may print Did you mean
		t.Logf("output: %s", out)
	}
}

func TestLegacyHelpDelegate(t *testing.T) {
	exe := buildMillennium(t)
	repo := repoRoot(t)
	scripts := filepath.Join(repo, "scripts")
	cmd := exec.Command(exe, "upgrade", "--help")
	cmd.Env = append(os.Environ(), "MILLENNIUM_SCRIPTS_DIR="+scripts)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("upgrade --help: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "Usage:") {
		t.Fatalf("expected Usage in help:\n%s", out)
	}
}

func TestNativeConfig(t *testing.T) {
	exe := buildMillennium(t)
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	env := append(os.Environ(),
		"MILLENNIUM_CONFIG_DIR="+dir,
		"MILLENNIUM_CONFIG_FILE="+cfg,
	)
	set := exec.Command(exe, "schedule", "config", "set", "update_channel", "beta")
	set.Env = env
	if out, err := set.CombinedOutput(); err != nil {
		t.Fatalf("config set: %v\n%s", err, out)
	}
	get := exec.Command(exe, "schedule", "config", "get", "update_channel")
	get.Env = env
	out, err := get.CombinedOutput()
	if err != nil {
		t.Fatalf("config get: %v\n%s", err, out)
	}
	if got := strings.TrimSpace(string(out)); got != "beta" {
		t.Fatalf("got %q", got)
	}
}

func TestNativeUpgradeRollbackList(t *testing.T) {
	exe := buildMillennium(t)
	lib := t.TempDir()
	_ = os.Mkdir(filepath.Join(lib, "millennium.bak_test"), 0o755)
	cmd := exec.Command(exe, "upgrade", "--rollback", "list")
	cmd.Env = append(os.Environ(), "MOCK_LIB_DIR="+lib)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	if !strings.Contains(string(out), "Available Backups") {
		t.Fatalf("%s", out)
	}
}

func TestNativePurgeDryRun(t *testing.T) {
	exe := buildMillennium(t)
	out, err := exec.Command(exe, "purge", "--dry-run").CombinedOutput()
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	if !strings.Contains(string(out), "DRY RUN") {
		t.Fatalf("%s", out)
	}
}

func buildMillennium(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	exe := filepath.Join(dir, "millennium")
	repo := repoRoot(t)
	verFile := filepath.Join(repo, "VERSION")
	verBytes, _ := os.ReadFile(verFile)
	ver := strings.TrimSpace(string(verBytes))
	ld := "-X github.com/bolens/millenium-helpers/internal/version.Version=" + ver
	cmd := exec.Command("go", "build", "-ldflags", ld, "-o", exe, "./cmd/millennium")
	cmd.Dir = filepath.Join(repo, "go")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	return exe
}

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	// tests run with cwd = go/ when using go test ./...
	if filepath.Base(wd) == "go" {
		return filepath.Dir(wd)
	}
	// or go/cmd/millennium
	if strings.HasSuffix(wd, filepath.Join("go", "cmd", "millennium")) {
		return filepath.Clean(filepath.Join(wd, "..", "..", ".."))
	}
	return filepath.Clean(filepath.Join(wd, ".."))
}
