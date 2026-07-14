package version

import "testing"

func TestResolveFallsBackToDev(t *testing.T) {
	old := Version
	Version = ""
	t.Cleanup(func() { Version = old })
	// When no VERSION is discoverable from a temp-like path, still returns non-empty.
	if got := Resolve(); got == "" {
		t.Fatal("Resolve() empty")
	}
}

func TestResolveHonorsLdflags(t *testing.T) {
	old := Version
	Version = "9.9.9"
	t.Cleanup(func() { Version = old })
	if got := Resolve(); got != "9.9.9" {
		t.Fatalf("got %q want 9.9.9", got)
	}
}
