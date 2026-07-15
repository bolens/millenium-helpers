package archive

import (
	"path/filepath"
	"runtime"
	"testing"
)

func TestSafeJoinDestRejectsSlip(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "out")
	cases := []string{
		"../evil.txt",
		"foo/../../evil.txt",
		"..\\evil.txt",
		"/etc/passwd",
	}
	if runtime.GOOS == "windows" {
		cases = append(cases, `C:\Windows\evil.txt`)
	}
	for _, member := range cases {
		if _, err := SafeJoinDest(dest, member); err == nil {
			t.Fatalf("expected rejection for %q", member)
		}
	}
}

func TestSafeJoinDestAcceptsSafe(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "out")
	got, err := SafeJoinDest(dest, "Theme/skin.json")
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(dest, "Theme", "skin.json")
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}
