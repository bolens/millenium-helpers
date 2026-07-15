package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestCommandFromArgv0(t *testing.T) {
	cases := map[string]string{
		"millennium-mcp":                 "mcp",
		"millennium-mcp.exe":             "mcp",
		"/usr/bin/millennium-upgrade":    "upgrade",
		`C:\bin\millennium-schedule.exe`: "schedule",
		"millennium-theme":               "theme",
		"millennium-diag":                "diag",
		"millennium-repair":              "repair",
		"millennium-purge":               "purge",
		"millennium":                     "",
		"other":                          "",
	}
	for in, want := range cases {
		if got := commandFromArgv0(in); got != want {
			t.Fatalf("commandFromArgv0(%q)=%q want %q", in, got, want)
		}
	}
}

func TestArgv0TwinSmoke(t *testing.T) {
	exe := buildMillennium(t)
	twinName := "millennium-upgrade"
	if runtime.GOOS == "windows" {
		twinName += ".exe"
	}
	twin := filepath.Join(t.TempDir(), twinName)
	in, err := os.ReadFile(exe)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(twin, in, 0o755); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command(twin, "--help").CombinedOutput()
	if err != nil {
		t.Fatalf("argv0 twin --help: %v\n%s", err, out)
	}
	text := string(out)
	if !strings.Contains(text, "Usage:") || !strings.Contains(strings.ToLower(text), "channel") {
		t.Fatalf("expected upgrade help from argv0 twin, got:\n%s", text)
	}
}

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

func TestNativeScheduleStatus(t *testing.T) {
	exe := buildMillennium(t)
	cfg := t.TempDir()
	cmd := exec.Command(exe, "schedule", "status")
	cmd.Env = append(os.Environ(),
		"MILLENNIUM_CONFIG_DIR="+cfg,
		"MILLENNIUM_CONFIG_FILE="+filepath.Join(cfg, "config.json"),
		"HOME="+cfg,
		"XDG_CONFIG_HOME="+filepath.Join(cfg, ".config"),
		"LOCALAPPDATA="+filepath.Join(cfg, "LocalAppData"),
		"APPDATA="+filepath.Join(cfg, "AppData"),
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("schedule status: %v\n%s", err, out)
	}
	text := string(out)
	if !strings.Contains(text, "Scheduler disabled") {
		t.Fatalf("expected disabled status:\n%s", text)
	}
	if !strings.Contains(text, "millennium schedule enable") {
		t.Fatalf("expected enable CTA:\n%s", text)
	}
}

func TestNativeScheduleEnableDisableDryRun(t *testing.T) {
	exe := buildMillennium(t)
	home := t.TempDir()
	env := append(os.Environ(),
		"HOME="+home,
		"XDG_CONFIG_HOME="+filepath.Join(home, ".config"),
		"LOCALAPPDATA="+filepath.Join(home, "LocalAppData"),
		"APPDATA="+filepath.Join(home, "AppData"),
		"MILLENNIUM_CONFIG_DIR="+filepath.Join(home, "cfg"),
		"MILLENNIUM_CONFIG_FILE="+filepath.Join(home, "cfg", "config.json"),
	)

	en := exec.Command(exe, "schedule", "enable", "stable", "--dry-run")
	en.Env = env
	enOut, err := en.CombinedOutput()
	if err != nil {
		t.Fatalf("enable --dry-run: %v\n%s", err, enOut)
	}
	text := string(enOut)
	if !strings.Contains(text, "DRY RUN") {
		t.Fatalf("enable missing DRY RUN:\n%s", text)
	}
	if !strings.Contains(text, "[DRY RUN] Would") {
		t.Fatalf("enable missing Would line:\n%s", text)
	}

	dis := exec.Command(exe, "schedule", "disable", "--dry-run")
	dis.Env = env
	disOut, err := dis.CombinedOutput()
	if err != nil {
		t.Fatalf("disable --dry-run: %v\n%s", err, disOut)
	}
	dtext := string(disOut)
	if !strings.Contains(dtext, "DRY RUN") {
		t.Fatalf("disable missing DRY RUN:\n%s", dtext)
	}
	if !strings.Contains(dtext, "[DRY RUN] Would") {
		t.Fatalf("disable missing Would line:\n%s", dtext)
	}
}

func TestNativeScheduleSetupWizard(t *testing.T) {
	exe := buildMillennium(t)
	home := t.TempDir()
	cfgDir := filepath.Join(home, "cfg")
	if err := os.MkdirAll(cfgDir, 0o700); err != nil {
		t.Fatal(err)
	}
	env := withEnv(os.Environ(), map[string]string{
		"HOME":                   home,
		"USERPROFILE":            home,
		"XDG_CONFIG_HOME":        filepath.Join(home, ".config"),
		"LOCALAPPDATA":           filepath.Join(home, "LocalAppData"),
		"APPDATA":                filepath.Join(home, "AppData"),
		"MILLENNIUM_CONFIG_DIR":  cfgDir,
		"MILLENNIUM_CONFIG_FILE": filepath.Join(cfgDir, "config.json"),
		"FORCE_WIZARD":           "true",
	})
	cmd := exec.Command(exe, "schedule", "setup", "--dry-run")
	cmd.Env = env
	cmd.Stdin = strings.NewReader("1\nn\n\n")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("setup --dry-run: %v\n%s", err, out)
	}
	text := string(out)
	for _, want := range []string{"Configuration Wizard", "[DRY RUN] Would write config", "update_channel: stable"} {
		if !strings.Contains(text, want) {
			t.Fatalf("setup missing %q:\n%s", want, text)
		}
	}
	if _, err := os.Stat(filepath.Join(cfgDir, "config.json")); err == nil {
		t.Fatal("dry-run must not write config.json")
	}
}

func TestNativeScheduleHooksGate(t *testing.T) {
	if testing.Short() {
		t.Skip("hooks smoke")
	}
	exe := buildMillennium(t)
	home := t.TempDir()
	env := append(os.Environ(),
		"HOME="+home,
		"MILLENNIUM_STATE_DIR="+filepath.Join(home, "state"),
		"MILLENNIUM_SCHEDULER=",
	)
	cmd := exec.Command(exe, "schedule", "pre-update")
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("expected gate failure, got:\n%s", out)
	}
	if !strings.Contains(string(out), "only for the scheduler") && !strings.Contains(string(out), "not used on Windows") {
		t.Fatalf("unexpected gate output:\n%s", out)
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

// withEnv returns base env with keys replaced (or added). Empty values unset.
func withEnv(base []string, kv map[string]string) []string {
	drop := make(map[string]struct{}, len(kv))
	for k := range kv {
		drop[k] = struct{}{}
	}
	out := make([]string, 0, len(base)+len(kv))
	for _, e := range base {
		k, _, ok := strings.Cut(e, "=")
		if ok {
			if _, skip := drop[k]; skip {
				continue
			}
		}
		out = append(out, e)
	}
	for k, v := range kv {
		if v == "" {
			continue
		}
		out = append(out, k+"="+v)
	}
	return out
}

func buildMillennium(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	name := "millennium"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	exe := filepath.Join(dir, name)
	repo := repoRoot(t)
	verFile := filepath.Join(repo, "VERSION")
	verBytes, _ := os.ReadFile(verFile)
	ver := strings.TrimSpace(string(verBytes))
	ld := "-X github.com/bolens/millenium-helpers/internal/version.Version=" + ver
	cmd := exec.Command("go", "build", "-buildvcs=false", "-ldflags", ld, "-o", exe, "./cmd/millennium")
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
