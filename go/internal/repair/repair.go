package repair

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/theme"
)

// Target is a path that repair would chown / touch.
type Target struct {
	Path string
	Kind string
}

// Plan lists ownership/cache repair targets for the current user (read-only).
func Plan() []Target {
	home, _ := os.UserHomeDir()
	xdgConfig := os.Getenv("XDG_CONFIG_HOME")
	if xdgConfig == "" {
		xdgConfig = filepath.Join(home, ".config")
	}
	xdgData := os.Getenv("XDG_DATA_HOME")
	if xdgData == "" {
		xdgData = filepath.Join(home, ".local", "share")
	}
	steam := theme.FindSteamDir()
	candidates := []string{
		filepath.Join(xdgData, "millennium"),
		filepath.Join(home, ".local", "share", "millennium"),
		filepath.Join(xdgConfig, "millennium"),
		filepath.Join(home, ".config", "millennium"),
		filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", "config", "millennium"),
		filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", ".config", "millennium"),
	}
	if steam != "" {
		candidates = append([]string{filepath.Join(steam, "millennium")}, candidates...)
	}
	var out []Target
	seen := map[string]bool{}
	for _, p := range candidates {
		if seen[p] {
			continue
		}
		if st, err := os.Stat(p); err == nil && (st.IsDir() || st.Mode().IsRegular()) {
			seen[p] = true
			out = append(out, Target{Path: p, Kind: "chown"})
		}
	}
	if steam != "" {
		cache := filepath.Join(steam, "config", "htmlcache")
		if st, err := os.Stat(cache); err == nil && st.IsDir() {
			out = append(out, Target{Path: cache, Kind: "htmlcache"})
		}
	}
	return out
}

// FormatPlan prints repair dry-run text.
func FormatPlan(targets []Target, skipTheme bool) string {
	var b strings.Builder
	b.WriteString("=== DRY RUN MODE: No changes will be made ===\n")
	b.WriteString("[DRY RUN] Would capture Steam's environment and close it if running.\n")
	if len(targets) == 0 {
		b.WriteString("[DRY RUN] No Millennium user/Steam paths found to repair.\n")
	}
	for _, t := range targets {
		b.WriteString(fmt.Sprintf("[DRY RUN] Would fix (%s): %s\n", t.Kind, t.Path))
	}
	if skipTheme {
		b.WriteString("[DRY RUN] Skipping theme refresh (--skip-theme).\n")
	} else {
		b.WriteString("[DRY RUN] Would refresh active theme assets if present.\n")
	}
	b.WriteString("Dry run completed successfully!\n")
	return b.String()
}

// Apply performs user-path repairs: clear htmlcache; chown when possible.
func Apply(targets []Target, skipTheme bool) error {
	for _, t := range targets {
		switch t.Kind {
		case "htmlcache":
			fmt.Printf("Clearing Steam htmlcache: %s\n", t.Path)
			entries, err := os.ReadDir(t.Path)
			if err != nil {
				return err
			}
			for _, e := range entries {
				if err := os.RemoveAll(filepath.Join(t.Path, e.Name())); err != nil {
					return err
				}
			}
		case "chown":
			fmt.Printf("Fixing ownership: %s\n", t.Path)
			if err := chownTree(t.Path); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: chown incomplete for %s: %v\n", t.Path, err)
			}
		}
	}
	if skipTheme {
		fmt.Println("Skipping theme refresh (--skip-theme).")
	} else {
		fmt.Println("Theme refresh: run 'millennium theme list' / legacy repair for full asset sync.")
	}
	return nil
}

// ParseFlags parses repair CLI flags.
func ParseFlags(args []string) (dryRun, yes, quiet, skipTheme, help bool, err error) {
	for _, a := range args {
		switch a {
		case "-d", "--dry-run", "-DryRun":
			dryRun = true
		case "-y", "--yes", "-Yes":
			yes = true
		case "-q", "--quiet", "-Quiet":
			quiet = true
		case "-s", "--skip-theme", "-SkipTheme":
			skipTheme = true
		case "-h", "--help", "-Help":
			help = true
		case "-V", "--version", "-Version":
		default:
			if strings.HasPrefix(a, "-") {
				return false, false, false, false, false, fmt.Errorf("Error: unknown option %s", a)
			}
		}
	}
	return dryRun, yes, quiet, skipTheme, help, nil
}

// RunCLI runs dry-run or live native repair for user-owned paths.
func RunCLI(dryRun, skipTheme, quiet bool) int {
	targets := Plan()
	if dryRun {
		fmt.Print(FormatPlan(targets, skipTheme))
		return 0
	}
	fmt.Println("Repairing Millennium paths (native user-path pass)...")
	if err := Apply(targets, skipTheme); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	if !quiet {
		fmt.Println("Repair completed (ownership/cache). Hook/binary reinstall still uses legacy 'millennium repair' via MILLENNIUM_LEGACY=1 when needed.")
	}
	return 0
}

// RunDryRunCLI prints a native repair plan.
func RunDryRunCLI(skipTheme bool) int {
	return RunCLI(true, skipTheme, false)
}
