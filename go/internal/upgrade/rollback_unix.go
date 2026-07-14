//go:build unix

package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func rollbackPlatform(backupName string, o Options) error {
	lib := LibDir()
	backupPath := filepath.Join(lib, backupName)
	dest := filepath.Join(lib, "millennium")
	if st, err := os.Stat(backupPath); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Backup '%s' not found.", backupName)
	}

	rollbackTemp := filepath.Join(lib, "millennium.rolled_back_"+rollbackTimestamp())
	movedActive := false
	if st, err := os.Stat(dest); err == nil && st.IsDir() {
		if err := os.Rename(dest, rollbackTemp); err != nil {
			return fmt.Errorf("Error: Failed to move active install aside: %w", err)
		}
		movedActive = true
	}
	if err := os.Rename(backupPath, dest); err != nil {
		if movedActive {
			_ = os.Rename(rollbackTemp, dest)
		}
		return fmt.Errorf("Error: Failed to swap backup: %w", err)
	}
	label := strings.TrimPrefix(backupName, "millennium.bak_")
	if !o.Quiet {
		fmt.Printf("Rollback successful! Backup %s is now active.\n", label)
	}
	if movedActive {
		oldVer := readVersionFile(rollbackTemp)
		movedBak := filepath.Join(lib, "millennium.bak_"+oldVer)
		_ = os.RemoveAll(movedBak)
		if err := os.Rename(rollbackTemp, movedBak); err != nil {
			return fmt.Errorf("Error: Rollback active but failed to save previous install: %w", err)
		}
		if !o.Quiet {
			fmt.Printf("Saved rolled back version to %s\n", filepath.Base(movedBak))
		}
	}
	return nil
}
