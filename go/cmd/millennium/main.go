package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/diag"
	"github.com/bolens/millenium-helpers/internal/legacy"
	"github.com/bolens/millenium-helpers/internal/purge"
	"github.com/bolens/millenium-helpers/internal/repair"
	"github.com/bolens/millenium-helpers/internal/suggest"
	"github.com/bolens/millenium-helpers/internal/theme"
	"github.com/bolens/millenium-helpers/internal/upgrade"
	"github.com/bolens/millenium-helpers/internal/version"
	"github.com/spf13/cobra"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	root := &cobra.Command{
		Use:   "millennium",
		Short: "Millennium helpers dispatcher (Go strangler)",
		Long: `Millennium helpers — unified dispatcher.

Native: version/help, schedule config, theme list, read-only diag,
upgrade rollback-list / dry-run / download+SHA, purge (Unix live) + dry-run,
repair user-path chown/htmlcache. Install/rollback extract still legacy
(see docs/unification-roadmap.md).

Force legacy for a native path: MILLENNIUM_LEGACY=1`,
		SilenceUsage:  true,
		SilenceErrors: true,
		Args:          cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 {
				return cmd.Help()
			}
			return fmt.Errorf("unknown command %q", args[0])
		},
	}

	root.PersistentFlags().BoolP("version", "V", false, "Show version information")
	root.SetArgs(args)

	if hasVersionOnly(args) {
		version.Print("millennium")
		return 0
	}

	root.AddCommand(newVersionCmd())
	root.AddCommand(newHelpAliasCmd(root))
	root.AddCommand(newScheduleCmd())
	root.AddCommand(newThemeCmd())
	root.AddCommand(newDiagCmd())
	root.AddCommand(newUpgradeCmd())
	root.AddCommand(newPurgeCmd())
	root.AddCommand(newRepairCmd())

	for _, name := range []string{"doctor", "mcp"} {
		n := name
		root.AddCommand(&cobra.Command{
			Use:                n,
			Short:              "Delegate to legacy millennium-" + displayBinary(n),
			DisableFlagParsing: true,
			RunE: func(cmd *cobra.Command, a []string) error {
				os.Exit(legacy.RunLegacy(n, a))
				return nil
			},
		})
	}

	if err := root.Execute(); err != nil {
		msg := err.Error()
		unknown := ""
		if _, after, ok := strings.Cut(msg, `unknown command "`); ok {
			unknown, _, _ = strings.Cut(after, `"`)
		}
		if unknown != "" {
			fmt.Fprintf(os.Stderr, "Error: unknown command '%s'\n", unknown)
			if s := suggest.Closest(unknown, legacy.KnownCommands()); s != "" {
				fmt.Fprintf(os.Stderr, "Did you mean '%s'?\n", s)
			}
		} else {
			fmt.Fprintln(os.Stderr, "Error:", msg)
			if tok := firstToken(args); tok != "" {
				if s := suggest.Closest(tok, legacy.KnownCommands()); s != "" {
					fmt.Fprintf(os.Stderr, "Did you mean '%s'?\n", s)
				}
			}
		}
		fmt.Fprintf(os.Stderr, "Try 'millennium --help' for usage.\n")
		return 1
	}
	return 0
}

func useLegacy() bool {
	v := strings.TrimSpace(os.Getenv("MILLENNIUM_LEGACY"))
	return v == "1" || strings.EqualFold(v, "true") || strings.EqualFold(v, "yes")
}

func newScheduleCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "schedule",
		Short:              "Scheduler / config (config is native Go; other actions legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if !useLegacy() {
				if rest, ok := takeConfigArgs(a); ok {
					os.Exit(config.RunCLI(rest))
					return nil
				}
			}
			os.Exit(legacy.RunLegacy("schedule", a))
			return nil
		},
	}
}

// takeConfigArgs returns (argsAfterConfig, true) when the schedule invocation is a config action.
func takeConfigArgs(a []string) ([]string, bool) {
	// Flags may appear before/after; find bare "config".
	idx := -1
	for i, tok := range a {
		if tok == "config" {
			idx = i
			break
		}
	}
	if idx < 0 {
		return nil, false
	}
	var out []string
	// Collect non-config flags from the whole argv plus tokens after config.
	for i, tok := range a {
		if i == idx {
			continue
		}
		if i < idx && (tok == "-d" || tok == "--dry-run" || tok == "-q" || tok == "--quiet" ||
			tok == "-DryRun" || tok == "-Quiet" || tok == "-h" || tok == "--help" || tok == "-Help") {
			out = append(out, tok)
			continue
		}
		if i < idx {
			// Other schedule commands mixed in — not pure config.
			if !strings.HasPrefix(tok, "-") {
				return nil, false
			}
			continue
		}
		out = append(out, tok)
	}
	return out, true
}

func newThemeCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "theme",
		Short:              "Themes (list is native Go; install/update/remove legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if !useLegacy() && isThemeList(a) {
				os.Exit(theme.RunListCLI(filterThemeListArgs(a)))
				return nil
			}
			os.Exit(legacy.RunLegacy("theme", a))
			return nil
		},
	}
}

func isThemeList(a []string) bool {
	if len(a) == 0 {
		return false
	}
	for _, tok := range a {
		if tok == "list" {
			return true
		}
		if tok == "install" || tok == "update" || tok == "remove" {
			return false
		}
	}
	return false
}

func filterThemeListArgs(a []string) []string {
	var out []string
	for _, tok := range a {
		if tok == "list" {
			continue
		}
		out = append(out, tok)
	}
	return out
}

func newDiagCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "diag",
		Short:              "Diagnostics (read-only summary native; doctor/json/share legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if !useLegacy() && !diag.NeedsLegacy(a) {
				os.Exit(diag.RunCLI(a))
				return nil
			}
			os.Exit(legacy.RunLegacy("diag", a))
			return nil
		},
	}
}

func newUpgradeCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "upgrade",
		Short:              "Upgrade Millennium (download+SHA native; install/rollback extract legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if useLegacy() {
				os.Exit(legacy.RunLegacy("upgrade", a))
				return nil
			}
			opts, err := upgrade.ParseArgs(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if opts.Version {
				version.Print("millennium-upgrade")
				os.Exit(0)
				return nil
			}
			handled, code := upgrade.RunNative(opts)
			if handled {
				os.Exit(code)
				return nil
			}
			legacyArgs := a
			if !opts.Rollback && opts.LocalFile == "" {
				path, sha, _, err := upgrade.FetchRemoteArchive(opts)
				if err != nil {
					fmt.Fprintln(os.Stderr, err.Error())
					os.Exit(1)
					return nil
				}
				if path == "" {
					os.Exit(0)
					return nil
				}
				defer os.Remove(path)
				legacyArgs = upgrade.ArgsForLocalFile(a, path, sha)
				if !opts.Quiet {
					fmt.Printf("Downloaded and verified %s; handing off to legacy installer…\n", filepath.Base(path))
				}
			}
			os.Exit(legacy.RunLegacy("upgrade", legacyArgs))
			return nil
		},
	}
}

func newPurgeCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "purge",
		Short:              "Purge Millennium (native dry-run + live Unix; Windows live legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if useLegacy() {
				os.Exit(legacy.RunLegacy("purge", a))
				return nil
			}
			dry, yes, quiet, help, err := purge.ParseFlags(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if help {
				fmt.Println("Usage: millennium purge [-d|--dry-run] [-y|--yes] [-q|--quiet]")
				os.Exit(0)
				return nil
			}
			if dry {
				os.Exit(purge.RunDryRunCLI())
				return nil
			}
			// Windows live purge stays on PowerShell (multi-path / Task Scheduler cleanup).
			if runtime.GOOS == "windows" {
				os.Exit(legacy.RunLegacy("purge", a))
				return nil
			}
			os.Exit(purge.RunCLI(false, yes, quiet))
			return nil
		},
	}
}

func newRepairCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "repair",
		Short:              "Repair Millennium (native user-path chown/htmlcache; hook reinstall via legacy)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			if useLegacy() {
				os.Exit(legacy.RunLegacy("repair", a))
				return nil
			}
			dry, _, quiet, skip, help, err := repair.ParseFlags(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if help {
				fmt.Println("Usage: millennium repair [-d|--dry-run] [-y|--yes] [-s|--skip-theme] [-q|--quiet]")
				os.Exit(0)
				return nil
			}
			os.Exit(repair.RunCLI(dry, skip, quiet))
			return nil
		},
	}
}

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Show version information",
		Run: func(cmd *cobra.Command, args []string) {
			version.Print("millennium")
		},
	}
}

func newHelpAliasCmd(root *cobra.Command) *cobra.Command {
	return &cobra.Command{
		Use:   "help",
		Short: "Show help",
		Run: func(cmd *cobra.Command, args []string) {
			_ = root.Help()
		},
	}
}

func displayBinary(name string) string {
	if name == "doctor" {
		return "diag (doctor)"
	}
	return name
}

func hasVersionOnly(args []string) bool {
	if len(args) != 1 {
		return false
	}
	switch args[0] {
	case "-V", "--version", "version":
		return true
	}
	return false
}

func firstToken(args []string) string {
	for _, a := range args {
		if strings.HasPrefix(a, "-") {
			continue
		}
		return a
	}
	if len(args) > 0 {
		return strings.TrimLeft(args[0], "-")
	}
	return ""
}
