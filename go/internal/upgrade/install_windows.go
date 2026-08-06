//go:build windows

package upgrade

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/bolens/millenium-helpers/internal/theme"
)

func installPlatform(archivePath, version string, o Options) error {
	steam := theme.FindSteamDir()
	if steam == "" {
		return fmt.Errorf("Steam directory not found")
	}
	stage, err := os.MkdirTemp("", "millennium-upgrade-stage-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)

	if err := theme.SafeExtractZip(archivePath, stage); err != nil {
		return err
	}

	entries, err := os.ReadDir(stage)
	if err != nil {
		return err
	}
	if len(entries) == 1 && entries[0].IsDir() {
		stage = filepath.Join(stage, entries[0].Name())
		entries, err = os.ReadDir(stage)
		if err != nil {
			return err
		}
	}
	oldVer := version
	mill := filepath.Join(steam, "millennium")
	if b, err := os.ReadFile(filepath.Join(mill, "version.txt")); err == nil {
		oldVer = strings.TrimSpace(string(b))
	}
	bakRoot := EffectiveBackupDir()
	if bakRoot == "" {
		bakRoot = filepath.Join(steam, "millennium_backups")
	}
	if err := os.MkdirAll(bakRoot, 0o755); err != nil {
		return fmt.Errorf("create backup root: %w", err)
	}
	// Back up every destination the archive will replace before mutating Steam.
	bak := filepath.Join(bakRoot, oldVer+"_"+time.Now().Format("20060102150405"))
	if err := os.Mkdir(bak, 0o755); err != nil {
		return fmt.Errorf("create backup: %w", err)
	}
	backedUp := false
	for _, e := range entries {
		dest := filepath.Join(steam, e.Name())
		if _, err := os.Lstat(dest); err == nil {
			if err := copyPath(dest, filepath.Join(bak, e.Name())); err != nil {
				_ = os.RemoveAll(bak)
				return fmt.Errorf("back up %s: %w", dest, err)
			}
			backedUp = true
		} else if !os.IsNotExist(err) {
			_ = os.RemoveAll(bak)
			return fmt.Errorf("inspect %s before backup: %w", dest, err)
		}
	}

	for _, e := range entries {
		src := filepath.Join(stage, e.Name())
		dest := filepath.Join(steam, e.Name())
		if err := os.RemoveAll(dest); err != nil {
			return restoreWindowsBackup(steam, bak, entries, fmt.Errorf("remove %s: %w", dest, err))
		}
		if e.IsDir() {
			if err := copyDirTree(src, dest); err != nil {
				return restoreWindowsBackup(steam, bak, entries, fmt.Errorf("install %s: %w", dest, err))
			}
		} else {
			if err := copyFile(src, dest); err != nil {
				return restoreWindowsBackup(steam, bak, entries, fmt.Errorf("install %s: %w", dest, err))
			}
		}
	}
	mill = filepath.Join(steam, "millennium")
	if err := os.MkdirAll(mill, 0o755); err != nil {
		return restoreWindowsBackup(steam, bak, entries, err)
	}
	if err := os.WriteFile(filepath.Join(mill, "version.txt"), []byte(version+"\n"), 0o644); err != nil {
		return restoreWindowsBackup(steam, bak, entries, err)
	}
	if !backedUp {
		_ = os.RemoveAll(bak)
	}
	InstallLicense(mill)
	if err := PruneBackups(); err != nil {
		return err
	}
	_ = o
	return nil
}

func copyPath(src, dst string) error {
	st, err := os.Stat(src)
	if err != nil {
		return err
	}
	if st.IsDir() {
		return copyDirTree(src, dst)
	}
	return copyFile(src, dst)
}

func restoreWindowsBackup(steam, bak string, entries []os.DirEntry, installErr error) error {
	var restoreErrs []string
	for _, e := range entries {
		dest := filepath.Join(steam, e.Name())
		if err := os.RemoveAll(dest); err != nil {
			restoreErrs = append(restoreErrs, err.Error())
			continue
		}
		backup := filepath.Join(bak, e.Name())
		if _, err := os.Lstat(backup); err == nil {
			if err := copyPath(backup, dest); err != nil {
				restoreErrs = append(restoreErrs, err.Error())
			}
		}
	}
	if len(restoreErrs) > 0 {
		return fmt.Errorf("%w; rollback also failed: %s", installErr, strings.Join(restoreErrs, "; "))
	}
	return fmt.Errorf("%w; previous installation restored", installErr)
}

func copyDirTree(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		return copyFile(path, target)
	})
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
