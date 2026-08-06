package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/logging"
	"github.com/bolens/millenium-helpers/internal/theme"
)

const licenseFallback = `MIT License

Copyright (c) 2026 Project Millennium

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
`

// CanNativeInstall reports whether this process can write the install root.
func CanNativeInstall() bool {
	if runtime.GOOS == "windows" {
		return theme.FindSteamDir() != ""
	}
	lib := LibDir()
	if err := os.MkdirAll(lib, 0o755); err != nil {
		return false
	}
	f, err := os.CreateTemp(lib, ".millennium-writetest-*")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name)
	return true
}

// InstallRoot returns the millenium directory that receives binaries.
func InstallRoot() string {
	if runtime.GOOS == "windows" {
		steam := theme.FindSteamDir()
		if steam == "" {
			return ""
		}
		return filepath.Join(steam, "millennium")
	}
	return filepath.Join(LibDir(), "millennium")
}

// InferVersion guesses a version string from filename or channel tag residue.
func InferVersion(archivePath, fallback string) string {
	base := filepath.Base(archivePath)
	if i := strings.Index(base, "-v"); i >= 0 {
		rest := base[i+2:]
		end := 0
		for j, c := range rest {
			if (c >= '0' && c <= '9') || c == '.' {
				end = j + 1
				continue
			}
			break
		}
		if end > 0 {
			return rest[:end]
		}
	}
	if fallback != "" {
		return strings.TrimPrefix(fallback, "v")
	}
	return time.Now().Format("20060102150405")
}

// InstallLicense writes DEST/LICENSE best-effort.
// Attribution and vendored notice policy: docs/licensing.md.
func InstallLicense(destDir string) {
	_ = os.WriteFile(filepath.Join(destDir, "LICENSE"), []byte(licenseFallback), 0o644)
}

// PruneBackups removes expired backups and then enforces the configured count.
func PruneBackups() error {
	limit := 5
	maxAgeDays := 0
	data, err := config.Load()
	if err != nil {
		// Retention is cleanup; malformed config must not block an otherwise
		// successful install or risk pruning with unintended defaults.
		return nil
	}
	if v := config.Get(data, "backup_limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	if v := config.Get(data, "backup_max_age_days"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			maxAgeDays = n
		}
	}

	root := LibDir()
	windowsLayout := runtime.GOOS == "windows"
	if windowsLayout {
		root = EffectiveBackupDir()
	}
	if root == "" {
		return nil
	}
	entries, err := os.ReadDir(root)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read backup directory: %w", err)
	}
	type backup struct {
		path    string
		modTime time.Time
	}
	var backs []backup
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if windowsLayout && !isWindowsBackupName(entry.Name()) {
			continue
		}
		if !windowsLayout && entry.Name() != "millennium.bak" && !strings.HasPrefix(entry.Name(), "millennium.bak_") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			return fmt.Errorf("inspect backup %s: %w", entry.Name(), err)
		}
		backs = append(backs, backup{path: filepath.Join(root, entry.Name()), modTime: info.ModTime()})
	}
	if maxAgeDays > 0 {
		cutoff := time.Now().Add(-time.Duration(maxAgeDays) * 24 * time.Hour)
		kept := backs[:0]
		for _, b := range backs {
			if b.modTime.Before(cutoff) {
				if err := os.RemoveAll(b.path); err != nil {
					return fmt.Errorf("remove expired backup %s: %w", b.path, err)
				}
				continue
			}
			kept = append(kept, b)
		}
		backs = kept
	}
	sort.Slice(backs, func(i, j int) bool {
		if backs[i].modTime.Equal(backs[j].modTime) {
			return backs[i].path < backs[j].path
		}
		return backs[i].modTime.Before(backs[j].modTime)
	})
	for len(backs) > limit {
		if err := os.RemoveAll(backs[0].path); err != nil {
			return fmt.Errorf("remove excess backup %s: %w", backs[0].path, err)
		}
		backs = backs[1:]
	}
	return nil
}

func isWindowsBackupName(name string) bool {
	i := strings.LastIndexByte(name, '_')
	if i <= 0 || len(name)-i-1 != len("20060102150405") {
		return false
	}
	for _, r := range name[i+1:] {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// TryNativeInstall installs from a verified local archive when CanNativeInstall.
func TryNativeInstall(o Options, archivePath, version string) (handled bool, code int) {
	if o.Rollback || o.DryRun {
		return false, 0
	}
	if !CanNativeInstall() {
		return false, 0
	}
	if archivePath == "" {
		archivePath = o.LocalFile
	}
	if archivePath == "" {
		return false, 0
	}
	if version == "" {
		version = InferVersion(archivePath, "")
	}
	fmt.Printf("Installing Millennium v%s (native)...\n", version)
	if err := installPlatform(archivePath, version, o); err != nil {
		fmt.Fprintf(os.Stderr, "Error: native install failed: %v\n", err)
		fmt.Fprintln(os.Stderr, "Hint: ensure the install root is writable, or re-run with sudo on Linux.")
		logging.PrintUpgradeFailureTips(err.Error())
		return true, 1
	}
	if !o.Quiet {
		fmt.Printf("Done. Installed Millennium v%s (%s channel).\n", version, o.Channel)
	}
	return true, 0
}
