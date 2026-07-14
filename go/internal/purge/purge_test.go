package purge

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestPlanFindsHook(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hook plan")
	}
	root := t.TempDir()
	steam := filepath.Join(root, "Steam")
	hook := filepath.Join(steam, "ubuntu12_32", "libXtst.so.6")
	if err := os.MkdirAll(filepath.Dir(hook), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/usr/lib/millennium/libXtst.so.6", hook); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STEAM", steam)
	t.Setenv("MILLENNIUM_SKINS_DIR", filepath.Join(steam, "steamui", "skins"))

	actions := Plan()
	found := false
	for _, a := range actions {
		if a.Kind == "hook32" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected hook32 in %#v", actions)
	}
	out := FormatPlan(actions)
	if !contains(out, "DRY RUN") {
		t.Fatalf("%s", out)
	}
}

func TestParseFlags(t *testing.T) {
	d, y, _, h, ver, err := ParseFlags([]string{"--dry-run", "-y"})
	if err != nil || !d || !y || h || ver {
		t.Fatalf("dry=%v yes=%v help=%v ver=%v err=%v", d, y, h, ver, err)
	}
	_, _, _, _, ver, err = ParseFlags([]string{"-Version"})
	if err != nil || !ver {
		t.Fatalf("version err=%v ver=%v", err, ver)
	}
}

func TestApplyRemovesHookAndClearsCache(t *testing.T) {
	root := t.TempDir()
	hook := filepath.Join(root, "hook")
	if err := os.WriteFile(hook, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	cache := filepath.Join(root, "htmlcache")
	if err := os.MkdirAll(filepath.Join(cache, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cache, "sub", "f"), []byte("c"), 0o644); err != nil {
		t.Fatal(err)
	}
	actions := []Action{
		{Path: hook, Kind: "hook32", Detail: "test"},
		{Path: cache, Kind: "htmlcache", Detail: "clear"},
	}
	if err := Apply(actions); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(hook); !os.IsNotExist(err) {
		t.Fatalf("hook still present: %v", err)
	}
	entries, err := os.ReadDir(cache)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("htmlcache not cleared: %#v", entries)
	}
}

func TestConfirmOrRefuseYes(t *testing.T) {
	if err := ConfirmOrRefuse(true, nil); err != nil {
		t.Fatal(err)
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
