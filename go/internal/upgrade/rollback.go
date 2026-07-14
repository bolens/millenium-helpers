package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/bolens/millenium-helpers/internal/theme"
)

// CanNativeRollback reports whether this process can apply a rollback in-process.
func CanNativeRollback() bool {
	return CanNativeInstall()
}

// ResolveBackupName picks a backup basename from ListBackups for a user target.
// Empty target: sole backup, else lexicographically last (matches non-TTY shell).
// Accepts full names (millennium.bak_X) or short ids (X).
func ResolveBackupName(target string) (string, error) {
	backs, err := ListBackups()
	if err != nil {
		return "", err
	}
	if len(backs) == 0 {
		return "", fmt.Errorf("Error: No backups available to roll back to.")
	}
	if target == "" {
		return backs[len(backs)-1], nil
	}
	for _, b := range backs {
		if b == target || b == "millennium.bak_"+target {
			return b, nil
		}
	}
	return "", fmt.Errorf("Error: Backup '%s' not found.", target)
}

// applyRollback performs platform rollback (caller ensured CanNativeRollback).
func applyRollback(o Options) int {
	name, err := ResolveBackupName(o.RollbackTarget)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	if o.DryRun {
		fmt.Println("=== DRY RUN MODE: No changes will be made ===")
		fmt.Printf("[DRY RUN] Would restore backup %s\n", name)
		return 0
	}
	if err := rollbackPlatform(name, o); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	return 0
}

// EffectiveBackupDir returns Windows millennium_backups (or override).
func EffectiveBackupDir() string {
	if d := BackupDir(); d != "" {
		return d
	}
	if runtime.GOOS == "windows" {
		if steam := theme.FindSteamDir(); steam != "" {
			return filepath.Join(steam, "millennium_backups")
		}
	}
	return ""
}

// UnixBackupPath returns LibDir/name for a Unix backup basename.
func UnixBackupPath(name string) string {
	return filepath.Join(LibDir(), name)
}

func readVersionFile(dir string) string {
	b, err := os.ReadFile(filepath.Join(dir, "version.txt"))
	if err != nil {
		return "unknown"
	}
	v := strings.TrimSpace(string(b))
	if v == "" {
		return "unknown"
	}
	return v
}

func rollbackTimestamp() string {
	return time.Now().Format("20060102150405")
}
