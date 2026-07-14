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
func InstallLicense(destDir string) {
	_ = os.WriteFile(filepath.Join(destDir, "LICENSE"), []byte(licenseFallback), 0o644)
}

// PruneBackups removes oldest millennium.bak_* dirs under LibDir beyond limit.
func PruneBackups() {
	limit := 5
	if data, err := config.Load(); err == nil {
		if v := config.Get(data, "backup_limit"); v != "" {
			if n, err := strconv.Atoi(v); err == nil && n > 0 {
				limit = n
			}
		}
	}
	lib := LibDir()
	var backs []string
	matches, _ := filepath.Glob(filepath.Join(lib, "millennium.bak_*"))
	backs = append(backs, matches...)
	if st, err := os.Stat(filepath.Join(lib, "millennium.bak")); err == nil && st.IsDir() {
		backs = append(backs, filepath.Join(lib, "millennium.bak"))
	}
	sort.Strings(backs)
	for len(backs) > limit {
		_ = os.RemoveAll(backs[0])
		backs = backs[1:]
	}
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
		fmt.Fprintln(os.Stderr, "Hint: re-run with MILLENNIUM_LEGACY=1 to use the shell/PS installer.")
		return true, 1
	}
	if !o.Quiet {
		fmt.Printf("Done. Installed Millennium v%s (%s channel).\n", version, o.Channel)
	}
	return true, 0
}
