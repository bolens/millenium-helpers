//go:build windows

package purge

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPlanWindowsPaths(t *testing.T) {
	steam := t.TempDir()
	mill := filepath.Join(steam, "millennium")
	bak := filepath.Join(steam, "millennium_backups")
	_ = os.MkdirAll(mill, 0o755)
	_ = os.MkdirAll(bak, 0o755)
	_ = os.WriteFile(filepath.Join(steam, "wsock32.dll"), []byte("dll"), 0o644)
	cfg := t.TempDir()
	t.Setenv("STEAM", steam)
	t.Setenv("MILLENNIUM_CONFIG_DIR", cfg)
	_ = os.WriteFile(filepath.Join(cfg, "config.json"), []byte("{}"), 0o644)

	actions := Plan()
	kinds := map[string]bool{}
	for _, a := range actions {
		kinds[a.Kind] = true
	}
	for _, want := range []string{"millennium_dir", "wsock32", "backups", "config_dir"} {
		if !kinds[want] {
			t.Fatalf("missing %s in %#v", want, actions)
		}
	}
	out := FormatPlan(actions)
	if !strings.Contains(out, "millennium") {
		t.Fatalf("%s", out)
	}
}

func TestApplyRemovesWindowsTree(t *testing.T) {
	root := t.TempDir()
	mill := filepath.Join(root, "millennium")
	_ = os.MkdirAll(filepath.Join(mill, "sub"), 0o755)
	_ = os.WriteFile(filepath.Join(mill, "sub", "f"), []byte("x"), 0o644)
	if err := Apply([]Action{{Path: mill, Kind: "millennium_dir", Detail: "t"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(mill); !os.IsNotExist(err) {
		t.Fatal("millennium still present")
	}
}
