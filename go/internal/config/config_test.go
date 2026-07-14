package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGetSetListRoundTrip(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_CONFIG_DIR", dir)
	t.Setenv("MILLENNIUM_CONFIG_FILE", filepath.Join(dir, "config.json"))

	data := Data{}
	if err := Set(data, "update_channel", "beta"); err != nil {
		t.Fatal(err)
	}
	if err := Set(data, "backup_limit", "10"); err != nil {
		t.Fatal(err)
	}
	if err := Save(data); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if got := Get(loaded, "update_channel"); got != "beta" {
		t.Fatalf("channel=%q", got)
	}
	if got := Get(loaded, "backup_limit"); got != "10" {
		t.Fatalf("limit=%q", got)
	}
	out := FormatList(loaded)
	if !contains(out, "update_channel") || !contains(out, "beta") {
		t.Fatalf("list output: %s", out)
	}
}

func TestSetRejectsBadChannel(t *testing.T) {
	err := Set(Data{}, "update_channel", "nope")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestRunCLI(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_CONFIG_DIR", dir)
	t.Setenv("MILLENNIUM_CONFIG_FILE", filepath.Join(dir, "config.json"))

	if code := RunCLI([]string{"set", "update_channel", "main"}); code != 0 {
		t.Fatalf("set exit %d", code)
	}
	if code := RunCLI([]string{"get", "update_channel"}); code != 0 {
		t.Fatalf("get exit %d", code)
	}
	b, _ := os.ReadFile(filepath.Join(dir, "config.json"))
	if !contains(string(b), "main") {
		t.Fatalf("file: %s", b)
	}
	if code := RunCLI([]string{"set", "update_channel", "bad"}); code == 0 {
		t.Fatal("expected validation failure")
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 ||
		(func() bool {
			for i := 0; i+len(sub) <= len(s); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		})())
}
