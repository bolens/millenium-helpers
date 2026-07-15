package repair

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/bolens/millenium-helpers/internal/theme"
)

// HookPlan is one planned bootstrap hook symlink.
type HookPlan struct {
	Hook   string
	Target string
	Steam  string
}

// MillenniumLibRoot returns the install root that holds bootstrap .so files.
func MillenniumLibRoot() string {
	if d := os.Getenv("MOCK_LIB_DIR"); d != "" {
		return filepath.Join(d, "millennium")
	}
	if d := os.Getenv("MILLENNIUM_LIB_DIR"); d != "" {
		return filepath.Join(d, "millennium")
	}
	return "/usr/lib/millennium"
}

// PlanHooks lists libXtst → bootstrap symlink pairs for existing Steam trees.
// Empty on Windows/Darwin (hooks are not used there).
func PlanHooks() []HookPlan {
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		return nil
	}
	root := MillenniumLibRoot()
	home, _ := os.UserHomeDir()
	cands := []string{
		filepath.Join(home, ".local/share/Steam"),
		filepath.Join(home, ".steam/steam"),
		filepath.Join(home, ".steam/root"),
		filepath.Join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
	}
	if steam := theme.FindSteamDir(); steam != "" {
		cands = append([]string{steam}, cands...)
	}
	seen := map[string]bool{}
	var out []HookPlan
	for _, steam := range cands {
		if seen[steam] {
			continue
		}
		seen[steam] = true
		if st, err := os.Stat(steam); err != nil || !st.IsDir() {
			continue
		}
		for _, arch := range []struct{ folder, lib string }{
			{"ubuntu12_32", "x86"},
			{"ubuntu12_64", "hhx64"},
		} {
			hook := filepath.Join(steam, arch.folder, "libXtst.so.6")
			target := filepath.Join(root, "libmillennium_bootstrap_"+arch.lib+".so")
			out = append(out, HookPlan{Hook: hook, Target: target, Steam: steam})
		}
	}
	return out
}

// InstallBootstrapHooks restores Millennium Steam bootstrap symlinks (Unix).
// No-op on Windows/Darwin. Shared by `millennium repair` and `diag doctor`.
func InstallBootstrapHooks() error {
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		return nil
	}
	plans := PlanHooks()
	if len(plans) == 0 {
		return fmt.Errorf("no Steam directories found to install hooks")
	}
	fixed := 0
	for _, p := range plans {
		if _, err := os.Stat(p.Target); err != nil {
			return fmt.Errorf("bootstrap library missing at %s (run upgrade first)", p.Target)
		}
		_ = os.MkdirAll(filepath.Dir(p.Hook), 0o755)
		_ = os.Remove(p.Hook)
		if err := os.Symlink(p.Target, p.Hook); err != nil {
			return fmt.Errorf("link %s: %w", p.Hook, err)
		}
		fmt.Printf("Fixed hook: %s -> %s\n", p.Hook, p.Target)
		fixed++
	}
	if fixed == 0 {
		return fmt.Errorf("no Steam directories found to install hooks")
	}
	return nil
}
