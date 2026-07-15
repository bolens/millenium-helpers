package install

import (
	"strings"
	"testing"
)

func TestSudoersLine(t *testing.T) {
	line := SudoersLine("alice", "/usr/local/bin")
	for _, want := range []string{
		"alice ALL=(ALL) NOPASSWD:",
		"/usr/local/bin/millennium upgrade",
		"/usr/local/bin/millennium-upgrade",
		"/usr/local/bin/millennium-diag",
	} {
		if !strings.Contains(line, want) {
			t.Fatalf("missing %q in %q", want, line)
		}
	}
}
