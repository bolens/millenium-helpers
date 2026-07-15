package schedule

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/steam"
)

// Test seams for non-interactive unit tests.
var (
	stdinInteractive = defaultStdinInteractive
	readPromptLine   = defaultReadLine
	readPromptSecret = defaultReadSecret
)

// Persistent stdin reader so piped multi-line wizard answers are not lost when
// bufio.Reader buffers ahead of a single prompt.
var stdinReader = bufio.NewReader(os.Stdin)

func defaultStdinInteractive() bool {
	if os.Getenv("FORCE_WIZARD") == "true" {
		return true
	}
	fi, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func defaultReadLine(prompt string) (string, error) {
	fmt.Fprint(os.Stderr, prompt)
	line, err := stdinReader.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

func defaultReadSecret(prompt string) (string, error) {
	// Piped / FORCE_WIZARD input is plain text (matches bash read -rs under redirection).
	return defaultReadLine(prompt)
}

func setupConfigDir(tu TargetUser) string {
	if d := os.Getenv("MILLENNIUM_CONFIG_DIR"); d != "" {
		return d
	}
	if f := os.Getenv("MILLENNIUM_CONFIG_FILE"); f != "" {
		return filepath.Dir(f)
	}
	curName := ""
	if tu.Name != "" {
		// Prefer real-user path when elevated.
		if effectiveUID() == 0 && tu.Name != "root" {
			return filepath.Join(tu.Home, ".config", "millennium-helpers")
		}
		curName = tu.Name
	}
	_ = curName
	return config.Dir()
}

func withSetupConfigDir(dir string, fn func() error) error {
	prevDir := os.Getenv("MILLENNIUM_CONFIG_DIR")
	prevFile := os.Getenv("MILLENNIUM_CONFIG_FILE")
	_ = os.Setenv("MILLENNIUM_CONFIG_DIR", dir)
	_ = os.Unsetenv("MILLENNIUM_CONFIG_FILE")
	defer func() {
		if prevDir == "" {
			_ = os.Unsetenv("MILLENNIUM_CONFIG_DIR")
		} else {
			_ = os.Setenv("MILLENNIUM_CONFIG_DIR", prevDir)
		}
		if prevFile == "" {
			_ = os.Unsetenv("MILLENNIUM_CONFIG_FILE")
		} else {
			_ = os.Setenv("MILLENNIUM_CONFIG_FILE", prevFile)
		}
	}()
	return fn()
}

// runSetup runs the interactive configuration wizard, then optionally enable.
func runSetup(o Options) int {
	if !stdinInteractive() {
		fmt.Fprintln(os.Stderr, "Error: Setup wizard must be run in an interactive terminal.")
		return 1
	}

	fmt.Println()
	fmt.Println("=== Millennium Helpers Configuration Wizard ===")
	fmt.Println("This wizard will guide you through the configuration of the Millennium Helpers.")
	fmt.Println()

	tu, err := ResolveTargetUser()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	cfgDir := setupConfigDir(tu)
	cfgPath := filepath.Join(cfgDir, "config.json")

	var existing config.Data
	_ = withSetupConfigDir(cfgDir, func() error {
		existing, _ = config.Load()
		return nil
	})

	channel, err := promptChannel(existing)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Selected channel: %s\n\n", channel)

	enableSched, err := promptEnableScheduler(cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	if runtimeIsWindows() {
		fmt.Printf("Automated task: %v\n\n", enableSched)
	} else {
		fmt.Printf("Automated timer: %v\n\n", enableSched)
	}

	token, err := promptGitHubToken(existing)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if o.DryRun {
		fmt.Printf("\n[DRY RUN] Would write config to %s:\n", cfgPath)
		fmt.Printf("update_channel: %s\n", channel)
		if token != "" {
			fmt.Println("github_token: [set]")
		} else {
			fmt.Println("github_token: (not set)")
		}
		fmt.Println("(other keys such as backup_limit are preserved)")
	} else {
		if err := withSetupConfigDir(cfgDir, func() error {
			data, _ := config.Load()
			if data == nil {
				data = config.Data{}
			}
			data["update_channel"] = channel
			data["github_token"] = token
			return config.Save(data)
		}); err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to write configuration: %v\n", err)
			return 1
		}
		if effectiveUID() == 0 && tu.Name != "root" {
			steam.ChownUser(cfgDir, tu.Name)
			steam.ChownUser(cfgPath, tu.Name)
		}
		fmt.Printf("\nConfiguration saved successfully to: %s\n", cfgPath)
	}

	_ = os.Setenv("CONFIG_UPDATE_CHANNEL", channel)
	_ = os.Setenv("GITHUB_TOKEN", token)

	if enableSched {
		if runtimeIsWindows() {
			fmt.Println("\nConfiguring background update scheduled task...")
		} else {
			fmt.Println("\nConfiguring background update scheduler...")
		}
		if code := runEnable(channel, o.Cron, o.DryRun, o.Quiet, o.SystemdScope); code != 0 {
			return code
		}
	}

	fmt.Println("\nTip: tune backup retention anytime with:")
	fmt.Println("  millennium schedule config set backup_limit 5")
	fmt.Println("  millennium schedule config set backup_max_age_days 30")
	return 0
}

func promptChannel(existing config.Data) (string, error) {
	defaultNum, defaultDesc := "1", "Stable"
	switch config.Get(existing, "update_channel") {
	case "beta":
		defaultNum, defaultDesc = "2", "Beta"
	case "main":
		defaultNum, defaultDesc = "3", "Main"
	}
	for {
		fmt.Println("Choose Millennium Update Channel:")
		fmt.Println("  1) Stable   — latest published release")
		fmt.Println("  2) Beta     — beta-tagged prereleases")
		fmt.Println("  3) Main     — tip-of-development prereleases (non-beta when available)")
		line, err := readPromptLine(fmt.Sprintf("Selection [1-3, default: %s (%s)]: ", defaultNum, defaultDesc))
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(line) == "" {
			line = defaultNum
		}
		switch strings.TrimSpace(line) {
		case "1":
			return "stable", nil
		case "2":
			return "beta", nil
		case "3":
			return "main", nil
		default:
			fmt.Println("Invalid selection. Please choose 1, 2, or 3.")
			fmt.Println()
		}
	}
}

func promptEnableScheduler(cfgPath string) (bool, error) {
	defaultSched, defaultDesc := "y", "Y/n"
	if CollectStatus().Configured {
		defaultSched, defaultDesc = "y", "Y/n"
	} else if fileExists(cfgPath) {
		defaultSched, defaultDesc = "n", "y/N"
	}
	label := "timer"
	if runtimeIsWindows() {
		label = "task"
	}
	for {
		line, err := readPromptLine(fmt.Sprintf("Would you like to enable the daily automated background update %s? [%s]: ", label, defaultDesc))
		if err != nil {
			return false, err
		}
		if strings.TrimSpace(line) == "" {
			line = defaultSched
		}
		switch strings.ToLower(strings.TrimSpace(line)) {
		case "y", "yes":
			return true, nil
		case "n", "no":
			return false, nil
		default:
			fmt.Println("Invalid option. Please enter y or n.")
			fmt.Println()
		}
	}
}

func promptGitHubToken(existing config.Data) (string, error) {
	existingToken := config.Get(existing, "github_token")
	if existingToken == "" {
		existingToken = os.Getenv("GITHUB_TOKEN")
	}
	fmt.Println("To avoid GitHub API rate limits during updates, you can store an optional Personal Access Token (PAT).")
	if existingToken != "" {
		fmt.Println("A PAT is already saved. Press Enter to keep it (it will not be cleared), or paste a new token to replace it.")
		tok, err := readPromptSecret("GitHub PAT [keep existing]: ")
		if err != nil {
			return "", err
		}
		fmt.Fprintln(os.Stderr)
		if strings.TrimSpace(tok) == "" {
			fmt.Println("Kept existing GitHub PAT (unchanged).")
			fmt.Println()
			return existingToken, nil
		}
		fmt.Println("New GitHub PAT saved (hidden).")
		fmt.Println()
		return strings.TrimSpace(tok), nil
	}
	fmt.Println("No PAT is configured yet. Press Enter to skip, or paste a token to save one.")
	tok, err := readPromptSecret("GitHub PAT [optional]: ")
	if err != nil {
		return "", err
	}
	fmt.Fprintln(os.Stderr)
	if strings.TrimSpace(tok) != "" {
		fmt.Println("GitHub PAT saved (hidden).")
		fmt.Println()
		return strings.TrimSpace(tok), nil
	}
	fmt.Println("No GitHub PAT saved.")
	fmt.Println()
	return "", nil
}

func runtimeIsWindows() bool { return runtime.GOOS == "windows" }
