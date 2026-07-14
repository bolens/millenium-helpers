package repair

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
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
	if runtime.GOOS == "windows" {
		if local := os.Getenv("LOCALAPPDATA"); local != "" {
			candidates = append(candidates, filepath.Join(local, "millennium"))
		}
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
	if runtime.GOOS == "windows" {
		b.WriteString(fmt.Sprintf("[DRY RUN] Would run: millennium upgrade --force --channel %s\n", updateChannel()))
	} else {
		hooks := PlanHooks()
		if len(hooks) == 0 {
			b.WriteString("[DRY RUN] Would restore bootstrap hooks (no Steam tree found yet).\n")
		} else {
			for _, h := range hooks {
				b.WriteString(fmt.Sprintf("[DRY RUN] Would link hook: %s -> %s\n", h.Hook, h.Target))
			}
		}
	}
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

// Apply performs live ownership/cache repairs and theme refresh.
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
	} else if err := refreshThemes(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: theme refresh: %v\n", err)
	}
	return nil
}

func refreshThemes() error {
	name := theme.ActiveThemeName()
	if name != "" {
		fmt.Printf("Refreshing theme '%s'...\n", name)
		if err := theme.UpdateOne(name, false); err != nil {
			return err
		}
		return nil
	}
	fmt.Println("No active theme configured; checking for installed themes to update...")
	if err := theme.UpdateAll(false); err != nil {
		// Missing Steam/skins is not a hard repair failure.
		fmt.Fprintf(os.Stderr, "Warning: %v\n", err)
	}
	return nil
}

func updateChannel() string {
	data, err := config.Load()
	if err != nil {
		return "stable"
	}
	ch := strings.TrimSpace(config.Get(data, "update_channel"))
	switch ch {
	case "stable", "beta", "main":
		return ch
	default:
		return "stable"
	}
}

// forceReinstallWindows runs native upgrade --force (Windows binary reinstall).
func forceReinstallWindows(yes bool) error {
	ch := updateChannel()
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	args := []string{"upgrade", "--channel", ch, "--force"}
	if yes {
		args = append(args, "--yes")
	}
	fmt.Printf("Force-reinstalling Millennium binaries (channel %s)...\n", ch)
	cmd := exec.Command(exe, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// ParseFlags parses repair CLI flags.
func ParseFlags(args []string) (dryRun, yes, quiet, skipTheme, help, version bool, err error) {
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
			version = true
		default:
			if strings.HasPrefix(a, "-") {
				return false, false, false, false, false, false, fmt.Errorf("Error: unknown option %s", a)
			}
		}
	}
	return dryRun, yes, quiet, skipTheme, help, version, nil
}

// RunCLI runs dry-run or live native repair (hooks/binary + ownership/cache/theme).
func RunCLI(dryRun, skipTheme, quiet, yes bool) int {
	targets := Plan()
	if dryRun {
		fmt.Print(FormatPlan(targets, skipTheme))
		return 0
	}

	fmt.Println("=== Initiating Millennium Repair ===")
	relaunch, err := ensureSteamClosedForRepair(yes)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}

	if runtime.GOOS == "windows" {
		if err := forceReinstallWindows(yes); err != nil {
			fmt.Fprintf(os.Stderr, "Error: force upgrade failed: %v\n", err)
			return 1
		}
	} else {
		if err := InstallBootstrapHooks(); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: hook reinstall: %v\n", err)
		}
	}

	if err := Apply(targets, skipTheme); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if relaunch {
		fmt.Println("Relaunching Steam...")
		relaunchSteamAfterRepair()
	}

	if !quiet {
		fmt.Println("Repair completed successfully.")
		if runtime.GOOS == "windows" {
			fmt.Println("Tip: millennium schedule status — re-enable the updater task if it was cleared.")
		} else {
			fmt.Println("Tip: millennium diag — verify hooks and schedule after repair.")
		}
	}
	return 0
}

// RunDryRunCLI prints a native repair plan.
func RunDryRunCLI(skipTheme bool) int {
	return RunCLI(true, skipTheme, false, false)
}
