package theme

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestListInstalled(t *testing.T) {
	root := t.TempDir()
	skins := filepath.Join(root, "steamui", "skins")
	themeDir := filepath.Join(skins, "DemoTheme")
	if err := os.MkdirAll(themeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	meta := map[string]string{"owner": "acme", "repo": "DemoTheme", "commit": "abcdef123456"}
	b, _ := json.Marshal(meta)
	if err := os.WriteFile(filepath.Join(themeDir, "metadata.json"), b, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_SKINS_DIR", skins)
	t.Setenv("STEAM", root)

	themes, gotSkins, err := ListInstalled()
	if err != nil {
		t.Fatal(err)
	}
	if gotSkins != skins {
		t.Fatalf("skins=%q", gotSkins)
	}
	if len(themes) != 1 || themes[0].Name != "DemoTheme" || themes[0].Type != "github" {
		t.Fatalf("%+v", themes)
	}
	js := FormatJSON(themes)
	if js == "[]" || !contains(js, "DemoTheme") {
		t.Fatalf("json=%s", js)
	}
	if code := RunListCLI([]string{"--json"}); code != 0 {
		t.Fatalf("exit %d", code)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (func() bool {
		for i := 0; i+len(sub) <= len(s); i++ {
			if s[i:i+len(sub)] == sub {
				return true
			}
		}
		return false
	})()
}
