package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/diag"
	"github.com/bolens/millenium-helpers/internal/install"
	"github.com/bolens/millenium-helpers/internal/legacy"
	"github.com/bolens/millenium-helpers/internal/mcp"
	"github.com/bolens/millenium-helpers/internal/purge"
	"github.com/bolens/millenium-helpers/internal/repair"
	"github.com/bolens/millenium-helpers/internal/schedule"
	"github.com/bolens/millenium-helpers/internal/suggest"
	"github.com/bolens/millenium-helpers/internal/theme"
	"github.com/bolens/millenium-helpers/internal/upgrade"
	"github.com/bolens/millenium-helpers/internal/version"
	"github.com/spf13/cobra"
)

func main() {
	args := os.Args[1:]
	// Packaged long-name PATH twins (same binary as `millennium <cmd>`).
	if cmd := commandFromArgv0(os.Args[0]); cmd != "" {
		args = append([]string{cmd}, args...)
	}
	os.Exit(run(args))
}

// commandFromArgv0 maps PATH twins (millennium-upgrade, …) onto dispatcher commands.
func commandFromArgv0(arg0 string) string {
	base := strings.ToLower(filepath.Base(arg0))
	// Windows paths may use '\' when tests run on Unix (filepath.Base won't split).
	if i := strings.LastIndexAny(base, `/\`); i >= 0 {
		base = base[i+1:]
	}
	base = strings.TrimSuffix(base, ".exe")
	switch base {
	case "millennium-mcp":
		return "mcp"
	case "millennium-upgrade":
		return "upgrade"
	case "millennium-schedule":
		return "schedule"
	case "millennium-theme":
		return "theme"
	case "millennium-diag":
		return "diag"
	case "millennium-repair":
		return "repair"
	case "millennium-purge":
		return "purge"
	default:
		return ""
	}
}

func run(args []string) int {
	root := &cobra.Command{
		Use:   "millennium",
		Short: "Millennium helpers dispatcher",
		Long: `Millennium helpers — unified Go dispatcher.

Implements schedule, theme, diag (report/json/share/logs/doctor), upgrade
(download/SHA/install/rollback + Linux sudo handoff), purge, repair,
install/uninstall helpers, and mcp JSON-RPC (see spec/cli-contract.yaml).

MILLENNIUM_LEGACY=1 is obsolete for Go-owned commands (they stay native).`,
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
	root.AddCommand(newMcpCmd())
	root.AddCommand(newInstallCmd())
	root.AddCommand(newUninstallCmd())

	root.AddCommand(&cobra.Command{
		Use:                "doctor",
		Short:              "Alias for millennium diag doctor",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			os.Exit(diag.RunCLI(append([]string{"doctor"}, a...)))
			return nil
		},
	})

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

func newScheduleCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "schedule",
		Short:              "Scheduler (config/status/enable/disable/setup/pre/post native)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
			if rest, ok := takeConfigArgs(a); ok {
				os.Exit(config.RunCLI(rest))
				return nil
			}
			opts, err := schedule.ParseArgs(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if opts.Version {
				version.Print("millennium-schedule")
				os.Exit(0)
				return nil
			}
			os.Exit(schedule.RunCLI(opts))
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
		Short:              "Themes (list/install/update/remove native Go)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
			opts, err := theme.ParseArgs(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if opts.Version {
				version.Print("millennium-theme")
				os.Exit(0)
				return nil
			}
			os.Exit(theme.RunCLI(opts))
			return nil
		},
	}
}

func newDiagCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "diag",
		Short:              "Diagnostics (report/json/share/logs/doctor native, including --follow)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
			opts, err := diag.ParseArgs(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if opts.Version {
				version.Print("millennium-diag")
				os.Exit(0)
				return nil
			}
			os.Exit(diag.RunCLI(a))
			return nil
		},
	}
}

func newUpgradeCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "upgrade",
		Short:              "Upgrade Millennium (download+SHA+install+rollback; Linux sudo handoff)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
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
			if opts.Rollback {
				if handled, code := upgrade.TrySudoRollbackHandoff(opts); handled {
					os.Exit(code)
					return nil
				}
				fmt.Fprintln(os.Stderr, "Error: rollback requires a writable install root (or sudo on Linux).")
				os.Exit(1)
				return nil
			}
			archivePath := opts.LocalFile
			ver := ""
			removeArchive := false
			if opts.LocalFile == "" {
				path, sha, tag, err := upgrade.FetchRemoteArchive(opts)
				if err != nil {
					fmt.Fprintln(os.Stderr, err.Error())
					os.Exit(1)
					return nil
				}
				if path == "" {
					os.Exit(0)
					return nil
				}
				archivePath = path
				ver = strings.TrimPrefix(tag, "v")
				opts.LocalFile = path
				opts.LocalSHA = sha
				removeArchive = true
			}
			if handled, code := upgrade.TryNativeInstall(opts, archivePath, ver); handled {
				if removeArchive {
					_ = os.Remove(archivePath)
				}
				os.Exit(code)
				return nil
			}
			if handled, code := upgrade.TrySudoInstallHandoff(opts, archivePath, opts.LocalSHA); handled {
				if removeArchive {
					_ = os.Remove(archivePath)
				}
				os.Exit(code)
				return nil
			}
			if removeArchive {
				_ = os.Remove(archivePath)
			}
			fmt.Fprintln(os.Stderr, "Error: cannot install Millennium (install root not writable).")
			if runtime.GOOS == "linux" {
				fmt.Fprintln(os.Stderr, "Hint: re-run with sudo, or set MILLENNIUM_LIB_DIR to a writable path.")
			} else if runtime.GOOS == "windows" {
				fmt.Fprintln(os.Stderr, "Hint: ensure Steam is installed and detectable.")
			} else {
				fmt.Fprintln(os.Stderr, "Hint: set MILLENNIUM_LIB_DIR to a writable path, or re-run as root.")
			}
			os.Exit(1)
			return nil
		},
	}
}

func newPurgeCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "purge",
		Short:              "Purge Millennium (native dry-run + live Unix/Windows)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
			dry, yes, quiet, help, ver, err := purge.ParseFlags(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if ver {
				version.Print("millennium-purge")
				os.Exit(0)
				return nil
			}
			if help {
				fmt.Println("Usage: millennium purge [-d|--dry-run] [-y|--yes] [-q|--quiet]")
				os.Exit(0)
				return nil
			}
			os.Exit(purge.RunCLI(dry, yes, quiet))
			return nil
		},
	}
}

func newRepairCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "repair",
		Short:              "Repair Millennium (hooks/force-upgrade, ownership, htmlcache, themes)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native — ignore MILLENNIUM_LEGACY.
			dry, yes, quiet, skip, help, ver, err := repair.ParseFlags(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(1)
				return nil
			}
			if ver {
				version.Print("millennium-repair")
				os.Exit(0)
				return nil
			}
			if help {
				fmt.Println("Usage: millennium repair [-d|--dry-run] [-y|--yes] [-s|--skip-theme] [-q|--quiet]")
				os.Exit(0)
				return nil
			}
			os.Exit(repair.RunCLI(dry, skip, quiet, yes))
			return nil
		},
	}
}

func newMcpCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "mcp",
		Short:              "MCP JSON-RPC server (stdio + --register)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			// Always native Go MCP — ignore MILLENNIUM_LEGACY.
			opts, err := mcp.ParseArgs(a)
			if err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				os.Exit(2)
				return nil
			}
			os.Exit(mcp.RunCLI(opts))
			return nil
		},
	}
}

func newInstallCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "install",
		Short:              "Install helpers (dispatcher, twins, completions, libs)",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			os.Exit(install.RunCLI("install", a))
			return nil
		},
	}
}

func newUninstallCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "uninstall",
		Short:              "Uninstall helpers",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, a []string) error {
			os.Exit(install.RunCLI("uninstall", a))
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
