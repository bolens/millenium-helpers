package injection

import "testing"

func TestParseArgs(t *testing.T) {
	o, err := ParseArgs([]string{"disable", "--dry-run", "--yes", "--quiet"})
	if err != nil {
		t.Fatal(err)
	}
	if o.Action != "disable" || !o.DryRun || !o.Yes || !o.Quiet {
		t.Fatalf("unexpected options: %+v", o)
	}
}

func TestParseArgsRejectsMultipleActions(t *testing.T) {
	if _, err := ParseArgs([]string{"disable", "enable"}); err == nil {
		t.Fatal("expected multiple actions to fail")
	}
}
