package injection

import (
	"fmt"
	"os"
	"strings"

	"golang.org/x/term"
)

// Options holds parsed injection command arguments.
type Options struct {
	Action  string
	DryRun  bool
	Yes     bool
	Quiet   bool
	Help    bool
	Version bool
}

// ParseArgs parses millennium injection argv.
func ParseArgs(args []string) (Options, error) {
	var o Options
	for _, arg := range args {
		switch arg {
		case "status", "disable", "enable":
			if o.Action != "" {
				return o, fmt.Errorf("Error: multiple injection actions (%s and %s).", o.Action, arg)
			}
			o.Action = arg
		case "-d", "--dry-run", "-DryRun":
			o.DryRun = true
		case "-y", "--yes", "-Yes":
			o.Yes = true
		case "-q", "--quiet", "-Quiet":
			o.Quiet = true
		case "-h", "--help", "-Help":
			o.Help = true
		case "-V", "--version", "-Version":
			o.Version = true
		default:
			if strings.HasPrefix(arg, "-") {
				return o, fmt.Errorf("Error: unknown option %s", arg)
			}
			return o, fmt.Errorf("Error: unknown injection action %q", arg)
		}
	}
	return o, nil
}

// RunCLI executes an injection action.
func RunCLI(o Options) int {
	if o.Help || o.Action == "" {
		fmt.Print(helpText())
		return 0
	}
	if o.Action == "status" {
		state, details, err := platformStatus()
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			return 1
		}
		fmt.Printf("Millennium injection: %s\n", state)
		for _, detail := range details {
			fmt.Println(detail)
		}
		return 0
	}
	if o.Action == "disable" && !o.DryRun {
		if err := confirmDisable(o.Yes, os.Stdin); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	details, err := platformSetEnabled(o.Action == "enable", o.DryRun)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}
	if !o.Quiet {
		for _, detail := range details {
			fmt.Println(detail)
		}
		if o.DryRun {
			fmt.Println("Dry run: no files were changed.")
		} else {
			fmt.Println("Restart Steam to apply the injection change.")
		}
	}
	return 0
}

func confirmDisable(yes bool, stdin *os.File) error {
	if yes {
		return nil
	}
	if stdin == nil || !term.IsTerminal(int(stdin.Fd())) {
		return fmt.Errorf("Error: Refusing to disable injection without confirmation in a non-interactive session.\nRe-run with --yes (or -y), or use --dry-run.")
	}
	fmt.Println("This disables Millennium injection but preserves its configuration, plugins, and themes.")
	fmt.Print("Continue? [y/N]: ")
	var response string
	_, _ = fmt.Fscanln(stdin, &response)
	if !strings.EqualFold(response, "y") && !strings.EqualFold(response, "yes") {
		return fmt.Errorf("Injection disable cancelled.")
	}
	return nil
}

func helpText() string {
	return `Usage: millennium injection <status|disable|enable> [options]

Temporarily disable or re-enable Millennium's Steam bootstrap injection while
preserving configuration, plugins, themes, and installed client files.

Options:
  -y, --yes       Skip confirmation when disabling
  -d, --dry-run   Show changes without modifying files
  -q, --quiet     Suppress informational output
  -V, --version   Show version information
  -h, --help      Show help
`
}
