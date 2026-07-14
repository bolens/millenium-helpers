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
	for _, args := range [][]string{
		{"version"},
		{"-V"},
		{"--version"},
	} {
		out, err := exec.Command(exe, args...).CombinedOutput()
		if err != nil {
			t.Fatalf("%v: %v\n%s", args, err, out)
		}
		if !strings.Contains(string(out), "millennium version") {
			t.Fatalf("%v unexpected output: %s", args, out)
		}
	}
}

func TestRootHelpSmoke(t *testing.T) {
	exe := buildMillennium(t)
	for _, args := range [][]string{
		{"--help"},
		{"help"},
	} {
		out, err := exec.Command(exe, args...).CombinedOutput()
		if err != nil {
			t.Fatalf("%v: %v\n%s", args, err, out)
		}
		text := string(out)
		for _, want := range []string{"Available Commands", "schedule", "mcp"} {
			if !strings.Contains(text, want) {
				t.Fatalf("%v missing %q in help:\n%s", args, want, text)
			}
		}
	}
}

func TestSuggestOnUnknown(t *testing.T) {
	exe := buildMillennium(t)
	cmd := exec.Command(exe, "upgrad")
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected non-zero exit, got: %s", out)
	}
	if !strings.Contains(string(out), "Did you mean 'upgrade'") {
		t.Fatalf("expected Did you mean 'upgrade', got:\n%s", out)
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
	list := exec.Command(exe, "schedule", "config", "list")
	list.Env = env
	listOut, err := list.CombinedOutput()
	if err != nil {
		t.Fatalf("config list: %v\n%s", err, listOut)
	}
	text := string(listOut)
	if !strings.Contains(text, "update_channel") || !strings.Contains(text, "beta") {
		t.Fatalf("config list missing channel:\n%s", text)
	}
}

func TestNativeThemeList(t *testing.T) {
	exe := buildMillennium(t)
	skins := t.TempDir()
	env := append(os.Environ(), "MILLENNIUM_SKINS_DIR="+skins)

	empty := exec.Command(exe, "theme", "list", "--json")
	empty.Env = env
	emptyOut, err := empty.CombinedOutput()
	if err != nil {
		t.Fatalf("theme list --json empty: %v\n%s", err, emptyOut)
	}
	if got := strings.TrimSpace(string(emptyOut)); got != "[]" {
		t.Fatalf("empty json: got %q", got)
	}

	localDir := filepath.Join(skins, "LocalSkin")
	if err := os.MkdirAll(localDir, 0o755); err != nil {
		t.Fatal(err)
	}
	ghDir := filepath.Join(skins, "DemoTheme")
	if err := os.MkdirAll(ghDir, 0o755); err != nil {
		t.Fatal(err)
	}
	meta := `{"owner":"acme","repo":"DemoTheme","commit":"abcdef123456"}`
	if err := os.WriteFile(filepath.Join(ghDir, "metadata.json"), []byte(meta), 0o644); err != nil {
		t.Fatal(err)
	}

	prose := exec.Command(exe, "theme", "list")
	prose.Env = env
	proseOut, err := prose.CombinedOutput()
	if err != nil {
		t.Fatalf("theme list: %v\n%s", err, proseOut)
	}
	text := string(proseOut)
	if !strings.Contains(text, "LocalSkin") || !strings.Contains(text, "Local / Manual") {
		t.Fatalf("missing local theme prose:\n%s", text)
	}
	if !strings.Contains(text, "DemoTheme") || !strings.Contains(text, "acme/DemoTheme") {
		t.Fatalf("missing github theme prose:\n%s", text)
	}

	js := exec.Command(exe, "theme", "list", "--json")
	js.Env = env
	jsOut, err := js.CombinedOutput()
	if err != nil {
		t.Fatalf("theme list --json: %v\n%s", err, jsOut)
	}
	raw := string(jsOut)
	for _, want := range []string{`"name":"LocalSkin"`, `"type":"local"`, `"name":"DemoTheme"`, `"owner":"acme"`, `"type":"github"`} {
		if !strings.Contains(raw, want) {
			t.Fatalf("json missing %s:\n%s", want, raw)
		}
	}
}

func TestNativeThemeMutate(t *testing.T) {
	// Offline gate only — live install/update hits GitHub (covered by unit mocks).
	exe := buildMillennium(t)
	skins := t.TempDir()
	env := append(os.Environ(), "MILLENNIUM_SKINS_DIR="+skins)

	bad := exec.Command(exe, "theme", "install", "not-a-valid")
	bad.Env = env
	badOut, err := bad.CombinedOutput()
	if err == nil {
		t.Fatalf("expected install format failure, got:\n%s", badOut)
	}
	if !strings.Contains(string(badOut), "owner/repo") {
		t.Fatalf("install format error:\n%s", badOut)
	}

	missing := exec.Command(exe, "theme", "remove", "MissingTheme", "--yes")
	missing.Env = env
	missOut, err := missing.CombinedOutput()
	if err == nil {
		t.Fatalf("expected remove missing failure, got:\n%s", missOut)
	}
	if !strings.Contains(string(missOut), "not installed") {
		t.Fatalf("remove missing error:\n%s", missOut)
	}

	local := filepath.Join(skins, "LocalSkin")
	if err := os.MkdirAll(local, 0o755); err != nil {
		t.Fatal(err)
	}
	upd := exec.Command(exe, "theme", "update", "LocalSkin")
	upd.Env = env
	updOut, err := upd.CombinedOutput()
	if err != nil {
		t.Fatalf("update local: %v\n%s", err, updOut)
	}
	if !strings.Contains(string(updOut), "does not have GitHub metadata") {
		t.Fatalf("update local skip:\n%s", updOut)
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
