package logging

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestQuiet(t *testing.T) {
	t.Setenv("MILLENNIUM_QUIET", "")
	if Quiet(false) {
		t.Fatal("expected not quiet")
	}
	if !Quiet(true) {
		t.Fatal("expected quiet flag")
	}
	t.Setenv("MILLENNIUM_QUIET", "1")
	if !Quiet(false) {
		t.Fatal("expected env quiet")
	}
}

func TestPrintUpgradeFailureTips(t *testing.T) {
	var buf bytes.Buffer
	old := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stderr = w
	PrintUpgradeFailureTips("boom")
	_ = w.Close()
	os.Stderr = old
	_, _ = buf.ReadFrom(r)
	out := buf.String()
	for _, want := range []string{"Upgrade failed: boom", "rollback list", "millennium diag", "--yes"} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in %q", want, out)
		}
	}
}
