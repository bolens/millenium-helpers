package theme

import (
	"archive/zip"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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
	if js == "[]" || !strings.Contains(js, "DemoTheme") {
		t.Fatalf("json=%s", js)
	}
	if code := RunListCLI([]string{"--json"}); code != 0 {
		t.Fatalf("exit %d", code)
	}
}

func TestSanitizeAndParse(t *testing.T) {
	if err := SanitizeComponent("../x", "theme name"); err == nil {
		t.Fatal("expected error")
	}
	o, r, err := ParseOwnerRepo("acme/Skin")
	if err != nil || o != "acme" || r != "Skin" {
		t.Fatalf("%s %s %v", o, r, err)
	}
}

func TestInstallAndRemove(t *testing.T) {
	skins := t.TempDir()
	t.Setenv("MILLENNIUM_SKINS_DIR", skins)

	prevCommit := latestCommit
	prevDL := downloadURL
	t.Cleanup(func() {
		latestCommit = prevCommit
		downloadURL = prevDL
	})
	latestCommit = func(owner, repo string) (string, error) {
		return "abc1234deadbeef", nil
	}
	downloadURL = func(url, dest string) error {
		return writeThemeZip(dest, "DemoSkin", "abc1234deadbeef")
	}

	if err := Install("acme/DemoSkin", true); err != nil {
		t.Fatal(err)
	}
	if err := Install("acme/DemoSkin", false); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(skins, "DemoSkin")
	if _, err := os.Stat(filepath.Join(target, "metadata.json")); err != nil {
		t.Fatal(err)
	}
	if err := Remove("DemoSkin", true, false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("still present: %v", err)
	}
}

func writeThemeZip(dest, repo, commit string) error {
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	root := repo + "-" + commit + "/"
	_, _ = zw.Create(root)
	w, err := zw.Create(root + "skin.json")
	if err != nil {
		return err
	}
	_, _ = w.Write([]byte(`{"name":"demo"}`))
	return zw.Close()
}

func TestParseArgsTheme(t *testing.T) {
	o, err := ParseArgs([]string{"install", "a/b", "--dry-run"})
	if err != nil || o.Action != "install" || o.Arg != "a/b" || !o.DryRun {
		t.Fatalf("%+v %v", o, err)
	}
}
