package repair

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPlanAndFormat(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, "cfg"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, "data"))
	steam := filepath.Join(home, ".local", "share", "Steam")
	mill := filepath.Join(steam, "millennium")
	if err := os.MkdirAll(mill, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STEAM", steam)

	targets := Plan()
	found := false
	for _, tg := range targets {
		if tg.Path == mill {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected millennium path in %#v", targets)
	}
	out := FormatPlan(targets, true)
	if !contains(out, "skip-theme") && !contains(out, "Skipping theme") {
		t.Fatalf("%s", out)
	}
}

func TestApplyHtmlcache(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "htmlcache")
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cache, "blob"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	mill := filepath.Join(root, "millennium")
	if err := os.MkdirAll(mill, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := Apply([]Target{
		{Path: mill, Kind: "chown"},
		{Path: cache, Kind: "htmlcache"},
	}, true); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(cache)
	if err != nil || len(entries) != 0 {
		t.Fatalf("cache %#v err=%v", entries, err)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
