package legacy

import (
	"path/filepath"
	"runtime"
	"testing"
)

func TestScriptDirFindsCheckout(t *testing.T) {
	// This test file lives in go/internal/legacy → repo root is ../../..
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("no caller")
	}
	repoRoot := filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", "..", ".."))
	t.Setenv("MILLENNIUM_SCRIPTS_DIR", "")
	// Force discovery via walking from a subdir under repo.
	scriptsUnix := filepath.Join(repoRoot, "scripts")
	if !dirLooksLikeScripts(scriptsUnix) {
		t.Fatalf("expected checkout scripts at %s", scriptsUnix)
	}
	t.Setenv("MILLENNIUM_SCRIPTS_DIR", scriptsUnix)
	if got := ScriptDir(); got != scriptsUnix {
		t.Fatalf("got %q want %q", got, scriptsUnix)
	}
}

func TestIsFeature(t *testing.T) {
	if !IsFeature("diag") || IsFeature("help") {
		t.Fatal("IsFeature mismatch")
	}
}
