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

func FuzzSafeJoinDest(f *testing.F) {
	for _, seed := range []string{
		"Theme/skin.json",
		"../evil",
		"/absolute",
		`C:\Windows\file`,
		"a/b/c",
		"",
	} {
		f.Add(seed)
	}
	dest := filepath.Join(string(filepath.Separator), "safe", "extract")
	f.Fuzz(func(t *testing.T, member string) {
		target, err := SafeJoinDest(dest, member)
		if err != nil {
			return
		}
		rel, err := filepath.Rel(dest, target)
		if err != nil {
			t.Fatal(err)
		}
		if rel == ".." || filepath.IsAbs(rel) || len(rel) >= 3 && rel[:3] == ".."+string(filepath.Separator) {
			t.Fatalf("escaped destination: member=%q target=%q", member, target)
		}
	})
}
