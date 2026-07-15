package steam

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestParseRelaunchEnv(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "relaunch.env")
	body := "export DISPLAY=':1'\nexport WAS_FLATPAK='true'\nexport STEAM_ARGS='-silent '\n"
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	m, err := ParseRelaunchEnv(p)
	if err != nil {
		t.Fatal(err)
	}
	if m["DISPLAY"] != ":1" || m["WAS_FLATPAK"] != "true" || m["STEAM_ARGS"] != "-silent " {
		t.Fatalf("%v", m)
	}
}

func TestIsSafeRelaunchStateFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "relaunch.env")
	if err := os.WriteFile(p, []byte("export WAS_FLATPAK='false'\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	name, _, err := TargetUser()
	if err != nil {
		t.Fatal(err)
	}
	if !IsSafeRelaunchStateFile(name, p) {
		t.Fatal("expected safe")
	}
	link := filepath.Join(dir, "link.env")
	if err := os.Symlink(p, link); err != nil {
		t.Fatal(err)
	}
	if IsSafeRelaunchStateFile(name, link) {
		t.Fatal("symlink must be rejected")
	}
}

func TestIsGameRunningMockProc(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux /proc")
	}
	root := t.TempDir()
	pid := filepath.Join(root, "4242")
	_ = os.MkdirAll(pid, 0o755)
	_ = os.WriteFile(filepath.Join(pid, "comm"), []byte("game\n"), 0o644)
	environ := "SteamAppId=730\x00HOME=/tmp\x00"
	_ = os.WriteFile(filepath.Join(pid, "environ"), []byte(environ), 0o644)
	t.Setenv("MOCK_PROC", root)
	if !IsGameRunning() {
		t.Fatal("expected game")
	}
	_ = os.WriteFile(filepath.Join(pid, "comm"), []byte("steam\n"), 0o644)
	if IsGameRunning() {
		t.Fatal("steam helper should be skipped")
	}
}
