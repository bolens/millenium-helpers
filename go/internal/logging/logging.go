package logging

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// Quiet reports whether INFO should be suppressed (caller flag or MILLENNIUM_QUIET).
func Quiet(flag bool) bool {
	if flag {
		return true
	}
	v := os.Getenv("MILLENNIUM_QUIET")
	return v != "" && v != "0" && v != "false"
}

func stamp() string {
	return time.Now().Format("2006-01-02 15:04:05")
}

func callerName() string {
	_, file, _, ok := runtime.Caller(2)
	if !ok {
		return "millennium"
	}
	return filepath.Base(file)
}

// Info writes an INFO line unless quiet.
func Info(quiet bool, format string, args ...any) {
	if Quiet(quiet) {
		return
	}
	msg := fmt.Sprintf(format, args...)
	fmt.Printf("[%s] [INFO] [%s] %s\n", stamp(), callerName(), msg)
}

// Warn writes a WARN line (always).
func Warn(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Printf("[%s] [WARN] [%s] %s\n", stamp(), callerName(), msg)
}

// Error writes an ERROR line to stderr (always).
func Error(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(os.Stderr, "[%s] [ERROR] [%s] %s\n", stamp(), callerName(), msg)
}

// PrintUpgradeFailureTips mirrors the former shell/PS upgrade failure helpers.
func PrintUpgradeFailureTips(detail string) {
	fmt.Fprintln(os.Stderr)
	if detail != "" {
		fmt.Fprintf(os.Stderr, "Upgrade failed: %s\n", detail)
	} else {
		fmt.Fprintln(os.Stderr, "Upgrade failed.")
	}
	fmt.Fprintln(os.Stderr, "Next steps:")
	fmt.Fprintln(os.Stderr, "  * millennium upgrade --rollback list   # list backups")
	fmt.Fprintln(os.Stderr, "  * millennium diag                     # check installation health")
	fmt.Fprintln(os.Stderr, "  * Re-run with --yes if Steam close confirmation blocked the update")
}
