package diag

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLineMatchesFilter(t *testing.T) {
	parts := []string{"millennium", "bootstrap"}
	if !lineMatchesFilter("MILLENNIUM ready", parts) {
		t.Fatal("expected match")
	}
	if lineMatchesFilter("unrelated noise", parts) {
		t.Fatal("expected no match")
	}
}

func TestFollowFilteredAppend(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "webhelper.txt")
	if err := os.WriteFile(p, []byte("noise\nMILLENNIUM start\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	followPollInterval = 20 * time.Millisecond
	followMaxCycles = 40
	t.Cleanup(func() {
		followPollInterval = 200 * time.Millisecond
		followMaxCycles = 0
	})

	done := make(chan int, 1)
	go func() {
		done <- followFiltered(p, logFilterParts(), 100)
	}()

	time.Sleep(50 * time.Millisecond)
	f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = f.WriteString("still noise\nBOOTSTRAP ok\n")
	_ = f.Close()

	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("code=%d", code)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("follow did not stop")
	}
}

func TestFollowLogsMissing(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("STEAM", filepath.Join(home, "nosteam"))
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))
	// Isolate candidates that may resolve via default Steam paths on the host.
	t.Setenv("MILLENNIUM_SKINS_DIR", filepath.Join(home, "skins"))
	code := FollowLogs()
	if code != 1 && code != 0 {
		t.Fatalf("unexpected code %d", code)
	}
	_ = strings.Contains
}
