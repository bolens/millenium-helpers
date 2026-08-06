//go:build windows

package upgrade

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/bolens/millenium-helpers/internal/steam"
	"github.com/bolens/millenium-helpers/internal/theme"
)

func rollbackPlatform(backupName string, o Options) error {
	steamDir := theme.FindSteamDir()
	if steamDir == "" {
		return fmt.Errorf("Error: Steam directory not found.")
	}
	bakRoot := EffectiveBackupDir()
	targetBackup := filepath.Join(bakRoot, backupName)
	if st, err := os.Stat(targetBackup); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Backup '%s' not found.", backupName)
	}

	steamRunning := steam.IsSteamRunning()
	if steamRunning {
		if err := steam.ConfirmClose(o.Yes); err != nil {
			return err
		}
	}

	millSrc, wsockSrc, err := resolveWindowsBackupContents(targetBackup)
	if err != nil {
		return err
	}
	if !o.Quiet {
		fmt.Printf("Rolling back Millennium installation to %s...\n", backupName)
	}
	stage, err := os.MkdirTemp(steamDir, ".millennium-rollback-stage-*")
	if err != nil {
		return fmt.Errorf("Error: Failed to create rollback staging directory: %w", err)
	}
	defer os.RemoveAll(stage)
	stagedMill := filepath.Join(stage, "millennium")
	if err := copyDirTree(millSrc, stagedMill); err != nil {
		return fmt.Errorf("Error: Failed to stage millennium restore: %w", err)
	}
	stagedWsock := ""
	if wsockSrc != "" {
		stagedWsock = filepath.Join(stage, "wsock32.dll")
		if err := copyFile(wsockSrc, stagedWsock); err != nil {
			return fmt.Errorf("Error: Failed to stage wsock32.dll restore: %w", err)
		}
	}
	if err := swapWindowsRollback(steamDir, stagedMill, stagedWsock); err != nil {
		return err
	}
	if err := os.RemoveAll(targetBackup); err != nil {
		return fmt.Errorf("Error: Rollback succeeded but failed to remove consumed backup: %w", err)
	}
	if !o.Quiet {
		fmt.Println("Rollback completed successfully.")
	}
	if steamRunning {
		steam.RelaunchBestEffort()
		if !o.Quiet {
			fmt.Println("Steam relaunched.")
		}
	}
	return nil
}

func swapWindowsRollback(steamDir, stagedMill, stagedWsock string) error {
	previous, err := os.MkdirTemp(steamDir, ".millennium-rollback-previous-*")
	if err != nil {
		return fmt.Errorf("Error: Failed to create rollback transaction: %w", err)
	}
	defer os.RemoveAll(previous)

	millDest := filepath.Join(steamDir, "millennium")
	wsockDest := filepath.Join(steamDir, "wsock32.dll")
	oldMill := filepath.Join(previous, "millennium")
	oldWsock := filepath.Join(previous, "wsock32.dll")
	hadMill, err := moveIfPresent(millDest, oldMill)
	if err != nil {
		return fmt.Errorf("Error: Failed to preserve current millennium: %w", err)
	}
	hadWsock, err := moveIfPresent(wsockDest, oldWsock)
	if err != nil {
		if hadMill {
			_ = os.Rename(oldMill, millDest)
		}
		return fmt.Errorf("Error: Failed to preserve current wsock32.dll: %w", err)
	}

	restorePrevious := func(cause error) error {
		_ = os.RemoveAll(millDest)
		_ = os.Remove(wsockDest)
		var restoreErr error
		if hadMill {
			restoreErr = os.Rename(oldMill, millDest)
		}
		if hadWsock {
			if err := os.Rename(oldWsock, wsockDest); err != nil && restoreErr == nil {
				restoreErr = err
			}
		}
		if restoreErr != nil {
			return fmt.Errorf("%w; restoring the previous installation also failed: %v", cause, restoreErr)
		}
		return fmt.Errorf("%w; previous installation restored", cause)
	}
	if err := os.Rename(stagedMill, millDest); err != nil {
		return restorePrevious(fmt.Errorf("Error: Failed to activate restored millennium: %w", err))
	}
	if stagedWsock != "" {
		if err := os.Rename(stagedWsock, wsockDest); err != nil {
			return restorePrevious(fmt.Errorf("Error: Failed to activate restored wsock32.dll: %w", err))
		}
	}
	return nil
}

func moveIfPresent(src, dst string) (bool, error) {
	if _, err := os.Lstat(src); err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	return true, os.Rename(src, dst)
}

// resolveWindowsBackupContents finds millennium tree + optional wsock32 in a backup dir.
// Supports PS layout (backup/millennium + backup/wsock32.dll) and flat Go layout
// (backup itself is the millennium tree).
func resolveWindowsBackupContents(bak string) (millSrc, wsockSrc string, err error) {
	nested := filepath.Join(bak, "millennium")
	if st, e := os.Stat(nested); e == nil && st.IsDir() {
		millSrc = nested
		w := filepath.Join(bak, "wsock32.dll")
		if _, e := os.Stat(w); e == nil {
			wsockSrc = w
		}
		return millSrc, wsockSrc, nil
	}
	if _, e := os.Stat(filepath.Join(bak, "version.txt")); e == nil {
		return bak, "", nil
	}
	return "", "", fmt.Errorf("Error: Backup '%s' does not contain a Millennium install.", filepath.Base(bak))
}
