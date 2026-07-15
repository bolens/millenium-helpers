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

	mill := filepath.Join(steam, "millennium")
	if st, err := os.Stat(mill); err == nil && st.IsDir() {
		bakRoot := EffectiveBackupDir()
		if bakRoot == "" {
			bakRoot = filepath.Join(steam, "millennium_backups")
		}
		_ = os.MkdirAll(bakRoot, 0o755)
		oldVer := version
		if b, err := os.ReadFile(filepath.Join(mill, "version.txt")); err == nil {
			oldVer = strings.TrimSpace(string(b))
		}
		// Match PowerShell layout: millennium_backups/<ver>_<ts>/{millennium,wsock32.dll}
		bak := filepath.Join(bakRoot, oldVer+"_"+time.Now().Format("20060102150405"))
		_ = os.MkdirAll(bak, 0o755)
		_ = copyDirTree(mill, filepath.Join(bak, "millennium"))
		wsock := filepath.Join(steam, "wsock32.dll")
		if _, err := os.Stat(wsock); err == nil {
			_ = copyFile(wsock, filepath.Join(bak, "wsock32.dll"))
		}
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
	for _, e := range entries {
		src := filepath.Join(stage, e.Name())
		dest := filepath.Join(steam, e.Name())
		if e.IsDir() {
			_ = os.RemoveAll(dest)
			if err := copyDirTree(src, dest); err != nil {
				return err
			}
		} else {
			if err := copyFile(src, dest); err != nil {
				return err
			}
		}
	}
	mill = filepath.Join(steam, "millennium")
	_ = os.MkdirAll(mill, 0o755)
	_ = os.WriteFile(filepath.Join(mill, "version.txt"), []byte(version+"\n"), 0o644)
	InstallLicense(mill)
	_ = o
	return nil
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
