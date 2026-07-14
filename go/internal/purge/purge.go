package purge

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/theme"
)

// Action is one planned purge step.
type Action struct {
	Path   string
	Kind   string // hook32, hook64, htmlcache, system_dir, etc.
	Detail string
}

// Plan builds a dry-run plan of Millennium removal targets.
func Plan() []Action {
	var out []Action
	for _, steam := range discoverSteamDirs() {
		for _, rel := range []struct {
			rel  string
			kind string
		}{
			{"ubuntu12_32/libXtst.so.6", "hook32"},
			{"ubuntu12_64/libXtst.so.6", "hook64"},
		} {
			p := filepath.Join(steam, filepath.FromSlash(rel.rel))
			if isMillenniumHook(p) {
				out = append(out, Action{Path: p, Kind: rel.kind, Detail: "symlink hook"})
			}
		}
		cache := filepath.Join(steam, "config", "htmlcache")
		if st, err := os.Stat(cache); err == nil && st.IsDir() {
			out = append(out, Action{Path: cache, Kind: "htmlcache", Detail: "clear contents"})
		}
	}
	if runtime.GOOS != "windows" {
		sys := "/usr/lib/millennium"
		if st, err := os.Stat(sys); err == nil && st.IsDir() {
			out = append(out, Action{Path: sys, Kind: "system_dir", Detail: "remove tree"})
		}
	}
	return out
}

func discoverSteamDirs() []string {
	var out []string
	seen := map[string]bool{}
	add := func(p string) {
		if p == "" || seen[p] {
			return
		}
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			seen[p] = true
			out = append(out, p)
		}
	}
	add(theme.FindSteamDir())
	home, _ := os.UserHomeDir()
	for _, c := range theme.SteamCandidates() {
		add(c)
	}
	// Extra homes (uid>=1000) skipped in Phase 3 native plan — current user + candidates enough for dry-run.
	_ = home
	return out
}

func isMillenniumHook(path string) bool {
	fi, err := os.Lstat(path)
	if err != nil {
		return false
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		return false
	}
	target, err := os.Readlink(path)
	if err != nil {
		return false
	}
	return strings.Contains(target, "millennium") || strings.Contains(target, "Millennium")
}

// FormatPlan prints dry-run output.
func FormatPlan(actions []Action) string {
	var b strings.Builder
	b.WriteString("=== DRY RUN MODE: No changes will be made ===\n")
	b.WriteString("[DRY RUN] Would run: millennium schedule disable\n")
	if len(actions) == 0 {
		b.WriteString("No Millennium hooks or system install paths detected.\n")
	}
	for _, a := range actions {
		b.WriteString(fmt.Sprintf("[DRY RUN] Would remove (%s): %s — %s\n", a.Kind, a.Path, a.Detail))
	}
	b.WriteString("Dry run completed successfully!\n")
	return b.String()
}

// Apply executes purge actions. htmlcache clears contents; others remove paths.
func Apply(actions []Action) error {
	for _, a := range actions {
		switch a.Kind {
		case "htmlcache":
			entries, err := os.ReadDir(a.Path)
			if err != nil {
				return err
			}
			for _, e := range entries {
				p := filepath.Join(a.Path, e.Name())
				if err := os.RemoveAll(p); err != nil {
					return fmt.Errorf("clear htmlcache %s: %w", p, err)
				}
			}
			fmt.Printf("Clearing Steam htmlcache: %s\n", a.Path)
		default:
			fmt.Printf("Removing (%s): %s\n", a.Kind, a.Path)
			if err := os.RemoveAll(a.Path); err != nil {
				return fmt.Errorf("remove %s: %w", a.Path, err)
			}
		}
	}
	return nil
}

// ConfirmOrRefuse ensures --yes or interactive tty confirmation.
func ConfirmOrRefuse(yes bool, stdin *os.File) error {
	if yes {
		return nil
	}
	if stdin == nil {
		stdin = os.Stdin
	}
	fi, err := stdin.Stat()
	if err != nil || (fi.Mode()&os.ModeCharDevice) == 0 {
		return fmt.Errorf("Error: Refusing to purge without confirmation in a non-interactive session.\nRe-run with --yes (or -y) to confirm, or use --dry-run to simulate.")
	}
	fmt.Println("This will permanently remove Millennium hooks, binaries, and related Steam files.")
	fmt.Print("Are you sure you want to continue? [y/N]: ")
	var resp string
	_, _ = fmt.Fscanln(stdin, &resp)
	if !strings.EqualFold(resp, "y") && !strings.EqualFold(resp, "yes") {
		return fmt.Errorf("Purge cancelled.")
	}
	return nil
}

// DisableSchedulerBestEffort runs millennium-schedule disable when available.
func DisableSchedulerBestEffort() {
	fmt.Println("Disabling Millennium auto-update scheduler (if configured)...")
	path, err := execLookPath("millennium-schedule")
	if err != nil {
		return
	}
	cmd := execCommand(path, "disable")
	_ = cmd.Run()
}

// test seams
var execLookPath = execLookPathReal
var execCommand = execCommandReal

func execLookPathReal(file string) (string, error) { return exec.LookPath(file) }
func execCommandReal(name string, arg ...string) *exec.Cmd {
	return exec.Command(name, arg...)
}

// ParseFlags returns dryRun/yes/quiet/help from purge argv.
func ParseFlags(args []string) (dryRun, yes, quiet, help bool, err error) {
	for _, a := range args {
		switch a {
		case "-d", "--dry-run", "-DryRun":
			dryRun = true
		case "-y", "--yes", "-Yes":
			yes = true
		case "-q", "--quiet", "-Quiet":
			quiet = true
		case "-h", "--help", "-Help":
			help = true
		case "-V", "--version", "-Version":
		default:
			if strings.HasPrefix(a, "-") {
				return false, false, false, false, fmt.Errorf("Error: unknown option %s", a)
			}
		}
	}
	return dryRun, yes, quiet, help, nil
}

// RunCLI runs dry-run or live native purge (Unix). Windows live should stay on legacy.
func RunCLI(dryRun, yes, quiet bool) int {
	if runtime.GOOS == "windows" && !dryRun {
		fmt.Fprintln(os.Stderr, "Error: native live purge on Windows is not implemented; use legacy or MILLENNIUM_LEGACY=1.")
		return 1
	}
	actions := Plan()
	if dryRun {
		fmt.Print(FormatPlan(actions))
		return 0
	}
	if err := ConfirmOrRefuse(yes, os.Stdin); err != nil {
		msg := err.Error()
		if msg == "Purge cancelled." {
			fmt.Println(msg)
			return 0
		}
		fmt.Fprintln(os.Stderr, msg)
		return 1
	}
	DisableSchedulerBestEffort()
	fmt.Println("Purging Millennium hooks and files...")
	if err := Apply(actions); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	if !quiet {
		fmt.Println("Millennium has been successfully purged from Steam!")
		fmt.Println("Tip: remove helper tools with sudo ./install.sh uninstall if you no longer need them.")
	}
	return 0
}

// RunDryRunCLI prints a native purge plan.
func RunDryRunCLI() int {
	return RunCLI(true, false, false)
}
