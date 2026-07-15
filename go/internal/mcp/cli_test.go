package mcp

import "testing"

func TestParseArgs(t *testing.T) {
	opts, err := ParseArgs([]string{"--version"})
	if err != nil || !opts.Version {
		t.Fatalf("version: opts=%+v err=%v", opts, err)
	}
	opts, err = ParseArgs([]string{"-r"})
	if err != nil || !opts.Register {
		t.Fatalf("register: opts=%+v err=%v", opts, err)
	}
	_, err = ParseArgs([]string{"--nope"})
	if err == nil {
		t.Fatal("expected error for unknown flag")
	}
}
