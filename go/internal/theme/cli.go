package theme

import (
	"fmt"
	"os"
	"strings"

	"github.com/bolens/millenium-helpers/internal/suggest"
)

// Options for theme CLI (list handled separately by RunListCLI).
type Options struct {
	Action  string // list|install|update|remove
	Arg     string // owner/repo, theme name, or empty / --all for update
	All     bool
	DryRun  bool
	Quiet   bool
	Yes     bool
	JSON    bool
	Help    bool
	Version bool
}

// ParseArgs parses millennium theme argv.
func ParseArgs(args []string) (Options, error) {
	var o Options
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "-h", "--help", "-Help":
			o.Help = true
		case "-V", "--version", "-Version":
			o.Version = true
		case "-d", "--dry-run", "-DryRun":
			o.DryRun = true
		case "-q", "--quiet", "-Quiet":
			o.Quiet = true
		case "-y", "--yes", "-Yes":
			o.Yes = true
		case "--json", "-Json", "-json":
			o.JSON = true
		case "-a", "--all":
			o.All = true
		case "list", "install", "update", "remove":
			if o.Action != "" {
				return o, fmt.Errorf("Error: multiple theme actions (%s and %s).", o.Action, a)
			}
			o.Action = a
			if (a == "install" || a == "remove" || a == "update") && i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				i++
				if args[i] == "--all" || args[i] == "-a" {
					o.All = true
				} else {
					o.Arg = args[i]
				}
			}
		default:
			if strings.HasPrefix(a, "-") {
				return o, fmt.Errorf("Error: unknown option %s", a)
			}
			if o.Action != "" && o.Arg == "" {
				o.Arg = a
				continue
			}
			cmds := []string{"list", "install", "update", "remove"}
			msg := fmt.Sprintf("Error: Unknown command '%s'", a)
			if s := suggest.Closest(a, cmds); s != "" {
				msg += fmt.Sprintf("\nDid you mean '%s'?", s)
			}
			return o, fmt.Errorf("%s", msg)
		}
	}
	return o, nil
}

// RunCLI runs list/install/update/remove. Exit code 0 on "Aborted." remove cancel.
func RunCLI(o Options) int {
	if o.Help {
		fmt.Print(`Usage: millennium theme <list|install|update|remove> [ARGS] [OPTIONS]

Native: list, install, update, remove (with --dry-run / --yes).

  list [--json]
  install owner/repo
  update [name|--all]
  remove name [-y|--yes]
`)
		return 0
	}
	if o.Action == "" {
		fmt.Print(`Usage: millennium theme <list|install|update|remove> [ARGS] [OPTIONS]

Native: list, install, update, remove (with --dry-run / --yes).

  list [--json]
  install owner/repo
  update [name|--all]
  remove name [-y|--yes]
`)
		return 1
	}
	if o.DryRun {
		fmt.Println("=== DRY RUN MODE: No changes will be made ===")
	}
	switch o.Action {
	case "list":
		args := []string{}
		if o.JSON {
			args = append(args, "--json")
		}
		return RunListCLI(args)
	case "install":
		if o.Arg == "" {
			fmt.Fprintln(os.Stderr, "Error: theme install requires owner/repo.")
			return 1
		}
		if err := Install(o.Arg, o.DryRun); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			// Already-exists warning from shell exits 1
			return 1
		}
		return 0
	case "update":
		if o.All || o.Arg == "" || o.Arg == "--all" {
			if err := UpdateAll(o.DryRun); err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				return 1
			}
			return 0
		}
		if err := UpdateOne(o.Arg, o.DryRun); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			return 1
		}
		return 0
	case "remove":
		if o.Arg == "" {
			fmt.Fprintln(os.Stderr, "Error: theme remove requires a theme name.")
			return 1
		}
		if err := Remove(o.Arg, o.Yes, o.DryRun); err != nil {
			if err.Error() == "Aborted." {
				fmt.Println("Aborted.")
				return 0
			}
			fmt.Fprintln(os.Stderr, err.Error())
			return 1
		}
		return 0
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown theme action %q\n", o.Action)
		return 1
	}
}
