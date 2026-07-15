package suggest

import "testing"

func TestClosestExact(t *testing.T) {
	cmds := []string{"diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp", "help"}
	if got := Closest("upgrade", cmds); got != "upgrade" {
		t.Fatalf("got %q", got)
	}
}

func TestClosestPrefix(t *testing.T) {
	cmds := []string{"diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp", "help"}
	if got := Closest("upg", cmds); got != "upgrade" {
		t.Fatalf("got %q want upgrade", got)
	}
}

func TestClosestEmpty(t *testing.T) {
	if got := Closest("", []string{"diag"}); got != "" {
		t.Fatalf("got %q", got)
	}
	if got := Closest("zzzz", []string{"diag", "help"}); got != "" {
		t.Fatalf("got unexpected %q", got)
	}
}
