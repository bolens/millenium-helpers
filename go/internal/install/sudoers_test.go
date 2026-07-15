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
		"/usr/local/bin/millennium diag",
		"/usr/local/bin/millennium repair",
		"/usr/local/bin/millennium purge",
	} {
		if !strings.Contains(line, want) {
			t.Fatalf("missing %q in %q", want, line)
		}
	}
	for _, avoid := range []string{
		"millennium-upgrade",
		"millennium-diag",
		"millennium-repair",
		"millennium-purge",
	} {
		if strings.Contains(line, avoid) {
			t.Fatalf("unexpected long-name allowlist %q in %q", avoid, line)
		}
	}
}
