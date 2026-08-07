package clientconfig

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

const usage = `Usage: millennium config <command> [arguments] [options]

Manage Millennium client settings without the Steam UI.

Commands:
  show                 Show current client settings
  plugins              List installed plugins and enabled state
  themes               List installed themes and active state
  errors               Show directly attributed recent plugin/theme errors
  enable NAME...       Enable installed plugins
  disable NAME...      Disable plugins
  theme NAME           Select an installed theme
  disable-theme [NAME] Reset the active theme to Steam
  disable-errors       Disable enabled/active components with attributed errors

Options:
  --json               Output show/plugins/themes as JSON
  -d, --dry-run        Show changes without writing
  -q, --quiet          Suppress mutation confirmation
  -y, --yes            Confirm disable-errors changes
  --plugins-only       With disable-errors, change only plugins
  --themes-only        With disable-errors, change only the active theme
  -V, --version        Show version information
  -h, --help           Show this help
`

// Options contains parsed config command arguments.
type Options struct {
	Action      string
	Names       []string
	JSON        bool
	DryRun      bool
	Quiet       bool
	Yes         bool
	PluginsOnly bool
	ThemesOnly  bool
	Help        bool
	Version     bool
}

// ParseArgs parses millennium config arguments.
func ParseArgs(args []string) (Options, error) {
	var result Options
	for _, arg := range args {
		switch arg {
		case "-h", "--help", "-Help":
			result.Help = true
		case "-V", "--version", "-Version":
			result.Version = true
		case "--json", "-Json":
			result.JSON = true
		case "-d", "--dry-run", "-DryRun":
			result.DryRun = true
		case "-q", "--quiet", "-Quiet":
			result.Quiet = true
		case "-y", "--yes", "-Yes":
			result.Yes = true
		case "--plugins-only":
			result.PluginsOnly = true
		case "--themes-only":
			result.ThemesOnly = true
		default:
			if strings.HasPrefix(arg, "-") {
				return result, fmt.Errorf("unknown option %s", arg)
			}
			if result.Action == "" {
				result.Action = arg
			} else {
				result.Names = append(result.Names, arg)
			}
		}
	}
	if result.Help || result.Version {
		return result, nil
	}
	switch result.Action {
	case "show", "plugins", "themes", "errors", "disable-errors":
		if len(result.Names) != 0 {
			return result, fmt.Errorf("config %s does not accept names", result.Action)
		}
	case "enable", "disable":
		if len(result.Names) == 0 {
			return result, fmt.Errorf("config %s requires at least one plugin name", result.Action)
		}
	case "theme":
		if len(result.Names) != 1 {
			return result, fmt.Errorf("config theme requires exactly one theme name")
		}
	case "disable-theme":
		if len(result.Names) > 1 {
			return result, fmt.Errorf("config disable-theme accepts at most one theme name")
		}
	case "":
		return result, fmt.Errorf("config command is required")
	default:
		return result, fmt.Errorf("unknown config command %q", result.Action)
	}
	if result.JSON && result.Action != "show" && result.Action != "plugins" && result.Action != "themes" && result.Action != "errors" {
		return result, fmt.Errorf("--json is only valid with show, plugins, themes, or errors")
	}
	mutation := result.Action == "enable" || result.Action == "disable" || result.Action == "theme" || result.Action == "disable-theme" || result.Action == "disable-errors"
	if result.DryRun && !mutation {
		return result, fmt.Errorf("--dry-run is only valid with configuration changes")
	}
	if result.Quiet && !mutation {
		return result, fmt.Errorf("--quiet is only valid with configuration changes")
	}
	if result.Yes && result.Action != "disable-errors" {
		return result, fmt.Errorf("--yes is only valid with disable-errors")
	}
	if result.Action == "disable-errors" && !result.DryRun && !result.Yes {
		return result, fmt.Errorf("config disable-errors requires --yes (or use --dry-run to preview)")
	}
	if (result.PluginsOnly || result.ThemesOnly) && result.Action != "disable-errors" {
		return result, fmt.Errorf("--plugins-only and --themes-only are only valid with disable-errors")
	}
	if result.PluginsOnly && result.ThemesOnly {
		return result, fmt.Errorf("--plugins-only and --themes-only cannot be combined")
	}
	return result, nil
}

func printJSON(value any) error {
	b, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

// RunCLI executes a parsed config command.
func RunCLI(options Options) int {
	if options.Help {
		fmt.Print(usage)
		return 0
	}
	var err error
	switch options.Action {
	case "show":
		var summary Summary
		summary, err = Show()
		if err == nil {
			if options.JSON {
				err = printJSON(summary)
			} else {
				fmt.Printf("activeTheme: %s\n", summary.ActiveTheme)
				fmt.Printf("millenniumUpdateChannel: %s\n", summary.MillenniumUpdateChannel)
				fmt.Printf("checkForMillenniumUpdates: %t\n", summary.CheckForMillenniumUpdates)
				fmt.Printf("checkForPluginAndThemeUpdates: %t\n", summary.CheckForPluginAndThemeUpdates)
				fmt.Printf("enabledPlugins: %s\n", strings.Join(summary.EnabledPlugins, ", "))
			}
		}
	case "plugins":
		var items []Plugin
		items, err = Plugins()
		if err == nil {
			if options.JSON {
				err = printJSON(items)
			} else {
				for _, item := range items {
					state := "disabled"
					if item.Enabled {
						state = "enabled"
					}
					fmt.Printf("%-9s %s\n", state, item.Name)
				}
			}
		}
	case "themes":
		var items []Theme
		items, err = Themes()
		if err == nil {
			if options.JSON {
				err = printJSON(items)
			} else {
				for _, item := range items {
					mark := " "
					if item.Active {
						mark = "*"
					}
					fmt.Printf("%s %s\n", mark, item.Name)
				}
			}
		}
	case "errors":
		var findings []Finding
		var path string
		findings, path, err = Errors()
		if err == nil {
			if options.JSON {
				err = printJSON(findings)
			} else if len(findings) == 0 {
				fmt.Printf("No directly attributed component errors found in %s.\n", path)
			} else {
				fmt.Printf("Recent directly attributed errors from %s:\n", path)
				for _, finding := range findings {
					state := "disabled"
					if finding.Enabled || finding.Active {
						state = "active"
					}
					fmt.Printf("%-6s %-9s %-24s %d error(s)\n", finding.Kind, state, finding.Name, finding.Count)
					fmt.Printf("  %s\n", finding.Evidence)
				}
			}
		}
	case "enable", "disable":
		enable := options.Action == "enable"
		err = SetPlugins(options.Names, enable, options.DryRun)
		if err == nil && !options.Quiet {
			if options.DryRun {
				fmt.Printf("[DRY RUN] Would %s plugins: %s\n", options.Action, strings.Join(options.Names, ", "))
			} else {
				fmt.Println("Restart Steam for changes to apply.")
			}
		}
	case "theme":
		err = SetTheme(options.Names[0], options.DryRun)
		if err == nil && !options.Quiet {
			if options.DryRun {
				fmt.Printf("[DRY RUN] Would set active theme to %s\n", options.Names[0])
			} else {
				fmt.Printf("Active theme set to %s. Restart Steam.\n", options.Names[0])
			}
		}
	case "disable-theme":
		expected := ""
		if len(options.Names) == 1 {
			expected = options.Names[0]
		}
		err = DisableTheme(expected, options.DryRun)
		if err == nil && !options.Quiet {
			if options.DryRun {
				fmt.Println("[DRY RUN] Would reset the active theme to Steam")
			} else {
				fmt.Println("Active theme reset to Steam. Restart Steam.")
			}
		}
	case "disable-errors":
		var findings []Finding
		findings, _, err = Errors()
		if err == nil {
			var plugins []string
			var theme string
			scope := "all"
			if options.PluginsOnly {
				scope = "plugins"
			} else if options.ThemesOnly {
				scope = "themes"
			}
			plugins, theme, err = DisableFlagged(findings, scope, options.DryRun)
			if err == nil && !options.Quiet {
				prefix := ""
				if options.DryRun {
					prefix = "[DRY RUN] "
				}
				if len(plugins) == 0 && theme == "" {
					fmt.Println("No enabled or active components have directly attributed errors.")
				} else {
					if len(plugins) > 0 {
						fmt.Printf("%sDisabled plugins: %s\n", prefix, strings.Join(plugins, ", "))
					}
					if theme != "" {
						fmt.Printf("%sReset theme %s to Steam\n", prefix, theme)
					}
					if !options.DryRun {
						fmt.Println("Restart Steam for changes to apply.")
					}
				}
			}
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}
	return 0
}

// Usage returns config command help text.
func Usage() string { return usage }
