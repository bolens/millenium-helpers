package legacy

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestScriptDirHonorsEnv(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_SCRIPTS_DIR", dir)
	if got := ScriptDir(); got != dir {
		t.Fatalf("got %q want %q", got, dir)
	}
}

func TestDirLooksLikeCheckoutScripts(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("no caller")
	}
	repoRoot := filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", "..", ".."))
	scriptsUnix := filepath.Join(repoRoot, "scripts")
	if !dirLooksLikeScripts(scriptsUnix) {
		t.Fatalf("expected checkout scripts at %s", scriptsUnix)
	}
	if runtime.GOOS == "windows" {
		win := filepath.Join(scriptsUnix, "windows")
		_ = os.MkdirAll(win, 0o755)
		if !dirLooksLikeScripts(win) {
			t.Fatalf("expected checkout scripts/windows at %s", win)
		}
	}
}

func TestIsFeature(t *testing.T) {
	if !IsFeature("diag") || IsFeature("help") {
		t.Fatal("IsFeature mismatch")
	}
}
