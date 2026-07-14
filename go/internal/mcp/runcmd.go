package mcp

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const (
	DefaultTimeout = 300 * time.Second
	LongTimeout    = 600 * time.Second
)

// CallResult is an MCP tools/call result payload.
type CallResult struct {
	Content []map[string]string `json:"content"`
	IsError bool                `json:"isError"`
}

func textResult(text string, isError bool) CallResult {
	return CallResult{
		Content: []map[string]string{{"type": "text", "text": text}},
		IsError: isError,
	}
}

func envTruthy(name string) bool {
	v := strings.TrimSpace(os.Getenv(name))
	return v == "1" || strings.EqualFold(v, "true") || strings.EqualFold(v, "yes")
}

// ForceLongNames reports whether tools should use millennium-* helpers.
func ForceLongNames() bool {
	return envTruthy("MILLENNIUM_MCP_LONGNAMES") || envTruthy("MILLENNIUM_LEGACY")
}

// FeatureArgv builds argv preferring this process binary (Go dispatcher).
func FeatureArgv(feature string, rest ...string) []string {
	if ForceLongNames() {
		return append([]string{"millennium-" + feature}, rest...)
	}
	exe := resolveExecutable()
	if exe == "" {
		return append([]string{"millennium", feature}, rest...)
	}
	return append([]string{exe, feature}, rest...)
}

// test seams
var osExecutable = os.Executable
var lookPath = exec.LookPath
var commandContext = exec.Command

func resolveExecutable() string {
	exe, err := osExecutable()
	if err != nil || exe == "" {
		return ""
	}
	return exe
}

func RunCmd(argv []string, elevate bool, timeout time.Duration) CallResult {
	if timeout <= 0 {
		timeout = DefaultTimeout
	}
	testSuite := envTruthy("TEST_SUITE_RUN")
	mockBin := os.Getenv("MOCK_BIN")

	exe := argv[0]
	rest := argv[1:]
	resolved := exe
	if !filepath.IsAbs(exe) {
		if p, err := lookPath(exe); err == nil {
			resolved = p
		} else if !testSuite {
			return textResult("Error: Command '"+exe+"' not found on system.", true)
		}
	} else if st, err := os.Stat(exe); err != nil || st.IsDir() {
		if !testSuite {
			return textResult("Error: Command '"+exe+"' not found on system.", true)
		}
		resolved = exe
	}

	cmdArgs := append([]string{resolved}, rest...)
	if elevate {
		if runtime.GOOS == "windows" {
			if sudo, err := lookPath("sudo.exe"); err == nil {
				cmdArgs = append([]string{sudo}, cmdArgs...)
			}
			// Without sudo.exe, elevating a non-PS1 is best-effort; tests
			// assert sudo -n on Unix. Production Windows uses UAC via hosts.
		} else {
			cmdArgs = append([]string{"sudo", "-n"}, cmdArgs...)
		}
	}

	if testSuite {
		return runUnderTestSuite(argv, cmdArgs, mockBin, timeout)
	}

	logf("Executing: %s", strings.Join(cmdArgs, " "))
	cmd := commandContext(cmdArgs[0], cmdArgs[1:]...)
	out, err := runWithTimeout(cmd, timeout)
	if err != nil {
		if _, ok := err.(timeoutError); ok {
			logf("Command timed out after %ds: %s", int(timeout.Seconds()), strings.Join(cmdArgs, " "))
			return textResult(
				"Error: Command '"+strings.Join(argv, " ")+"' timed out after "+
					strconv.Itoa(int(timeout.Seconds()))+" seconds and was terminated.",
				true,
			)
		}
		msg := strings.TrimSpace(out)
		if msg == "" {
			msg = err.Error()
		}
		return textResult(msg, true)
	}
	msg := strings.TrimSpace(out)
	if msg == "" {
		msg = "Command finished with exit code 0"
	}
	return textResult(msg, false)
}

func runUnderTestSuite(argv, cmdArgs []string, mockBin string, timeout time.Duration) CallResult {
	logf("Executing: %s", strings.Join(cmdArgs, " "))
	mockKey := filepath.Base(argv[0])
	mockPath := ""
	if mockBin != "" {
		mockPath = filepath.Join(mockBin, mockKey)
	}
	if mockPath != "" {
		if st, err := os.Stat(mockPath); err == nil && !st.IsDir() {
			cmd := commandContext(mockPath, argv[1:]...)
			out, err := runWithTimeout(cmd, timeout)
			msg := strings.TrimSpace(out)
			if msg == "" {
				if err != nil {
					msg = "Command finished with exit code 1"
				} else {
					msg = "Command finished with exit code 0"
				}
			}
			return textResult(msg, err != nil)
		}
	}
	logf("[TEST] Skipping host execution to protect Steam/system state")
	return textResult("[TEST] Skipped host execution", false)
}

type timeoutError struct{}

func (timeoutError) Error() string { return "timeout" }

func runWithTimeout(cmd *exec.Cmd, timeout time.Duration) (string, error) {
	var buf strings.Builder
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Start(); err != nil {
		return "", err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return buf.String(), err
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		<-done
		return buf.String(), timeoutError{}
	}
}
