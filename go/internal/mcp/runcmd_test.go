package mcp

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestRunCmdTestSuiteSkipsWithoutMock(t *testing.T) {
	t.Setenv("TEST_SUITE_RUN", "1")
	t.Setenv("MOCK_BIN", t.TempDir())
	t.Setenv("MILLENNIUM_MCP_LONGNAMES", "1")

	r := RunCmd([]string{"millennium-repair"}, true, time.Second)
	if r.IsError {
		t.Fatalf("skip should not be error: %+v", r)
	}
	if !strings.Contains(r.Content[0]["text"], "Skipped host execution") {
		t.Fatalf("unexpected text: %+v", r)
	}
}

func TestRunCmdTimeout(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("timeout seam uses sleep")
	}
	dir := t.TempDir()
	hang := filepath.Join(dir, "mcp-hang-test")
	if err := os.WriteFile(hang, []byte("#!/bin/sh\nsleep 5\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	prevLook := lookPath
	lookPath = func(file string) (string, error) {
		if file == "mcp-hang-test" {
			return hang, nil
		}
		return prevLook(file)
	}
	defer func() { lookPath = prevLook }()

	// Avoid TEST_SUITE_RUN skip path
	t.Setenv("TEST_SUITE_RUN", "")
	r := RunCmd([]string{"mcp-hang-test"}, false, time.Second)
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "timed out") {
		t.Fatalf("timeout: %+v", r)
	}
}

func TestRunCmdUsesMockUnderTestSuite(t *testing.T) {
	dir := t.TempDir()
	mock := filepath.Join(dir, "millennium")
	if err := os.WriteFile(mock, []byte("#!/bin/sh\necho mock-ok\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("TEST_SUITE_RUN", "1")
	t.Setenv("MOCK_BIN", dir)
	t.Setenv("MILLENNIUM_MCP_LONGNAMES", "")
	t.Setenv("MILLENNIUM_LEGACY", "")
	prev := osExecutable
	osExecutable = func() (string, error) { return mock, nil }
	defer func() { osExecutable = prev }()

	r := RunCmd(FeatureArgv("diag", "--json"), false, time.Second)
	if r.IsError || !strings.Contains(r.Content[0]["text"], "mock-ok") {
		t.Fatalf("mock: %+v", r)
	}
}

func TestToolsListHasConfirm(t *testing.T) {
	found := false
	for _, tool := range ToolsList() {
		if tool.Name == "millennium_purge" {
			props, _ := tool.InputSchema["properties"].(map[string]any)
			if _, ok := props["confirm"]; ok {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("millennium_purge missing confirm")
	}
}
