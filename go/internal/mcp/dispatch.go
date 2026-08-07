package mcp

import (
	"fmt"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

var (
	// @@cli-contract:mcp.dispatch_allowlists@@
	validThemeActions    = map[string]bool{"list": true, "install": true, "remove": true, "update": true}
	validConfigActions   = map[string]bool{"show": true, "plugins": true, "themes": true, "errors": true, "enable": true, "disable": true, "theme": true, "disable-theme": true, "disable-errors": true}
	validScheduleActions = map[string]bool{"enable": true, "disable": true, "status": true}
	validChannels        = map[string]bool{"stable": true, "beta": true, "main": true}
	// @@/cli-contract:mcp.dispatch_allowlists@@
	themeRe    = regexp.MustCompile(`^[a-zA-Z0-9_\-\./:]+$`)
	rollbackRe = regexp.MustCompile(`^[a-zA-Z0-9_\-\.]+$`)
)

func sortedKeys(m map[string]bool) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return strings.Join(keys, ", ")
}

func boolArg(args map[string]any, key string) bool {
	v, ok := args[key]
	if !ok || v == nil {
		return false
	}
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return t == "1" || strings.EqualFold(t, "true") || strings.EqualFold(t, "yes")
	default:
		return false
	}
}

func stringArg(args map[string]any, key string) string {
	v, ok := args[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	default:
		return fmt.Sprint(t)
	}
}

func stringSliceArg(args map[string]any, key string) ([]string, bool) {
	v, ok := args[key]
	if !ok || v == nil {
		return nil, true
	}
	switch values := v.(type) {
	case []string:
		return values, true
	case []any:
		result := make([]string, 0, len(values))
		for _, value := range values {
			text, ok := value.(string)
			if !ok {
				return nil, false
			}
			result = append(result, text)
		}
		return result, true
	case string:
		return []string{values}, true
	default:
		return nil, false
	}
}

func validClientName(name string) bool {
	return name != "" && name != "." && name != ".." && len(name) <= 255 &&
		!strings.ContainsAny(name, `/\\\x00\r\n`)
}

// HandleToolCall validates arguments and runs the underlying CLI.
func HandleToolCall(toolName string, arguments map[string]any) CallResult {
	if arguments == nil {
		arguments = map[string]any{}
	}
	switch toolName {
	case "millennium_diag":
		doctor := boolArg(arguments, "doctor")
		if doctor {
			return RunCmd(FeatureArgv("diag", "doctor"), true, DefaultTimeout)
		}
		return RunCmd(FeatureArgv("diag", "--json"), false, DefaultTimeout)

	case "millennium_config":
		action := stringArg(arguments, "action")
		names, namesOK := stringSliceArg(arguments, "names")
		dryRun := boolArg(arguments, "dry_run")
		confirm := boolArg(arguments, "confirm")
		pluginsOnly := boolArg(arguments, "plugins_only")
		themesOnly := boolArg(arguments, "themes_only")
		if !validConfigActions[action] {
			return textResult(
				fmt.Sprintf("Error: invalid action '%s'. Must be one of: %s.", action, sortedKeys(validConfigActions)),
				true,
			)
		}
		if !namesOK {
			return textResult("Error: names must be an array of strings.", true)
		}
		for _, name := range names {
			if !validClientName(name) {
				return textResult("Error: plugin/theme name contains invalid characters.", true)
			}
		}
		if pluginsOnly && themesOnly {
			return textResult("Error: plugins_only and themes_only cannot both be true.", true)
		}
		if (pluginsOnly || themesOnly) && action != "disable-errors" {
			return textResult("Error: plugins_only and themes_only are only valid with disable-errors.", true)
		}
		if confirm && action != "disable-errors" {
			return textResult("Error: confirm is only valid with disable-errors.", true)
		}
		readAction := action == "show" || action == "plugins" || action == "themes" || action == "errors"
		if dryRun && readAction {
			return textResult("Error: dry_run is only valid with configuration changes.", true)
		}
		rest := []string{action}
		switch action {
		case "show", "plugins", "themes", "errors":
			if len(names) != 0 {
				return textResult("Error: names are not accepted for this read action.", true)
			}
			rest = append(rest, "--json")
		case "enable", "disable":
			if len(names) == 0 {
				return textResult("Error: at least one plugin name is required.", true)
			}
			rest = append(rest, names...)
		case "theme":
			if len(names) != 1 {
				return textResult("Error: exactly one theme name is required.", true)
			}
			rest = append(rest, names[0])
		case "disable-theme":
			if len(names) > 1 {
				return textResult("Error: disable-theme accepts at most one expected theme name.", true)
			}
			rest = append(rest, names...)
		case "disable-errors":
			if len(names) != 0 {
				return textResult("Error: names are not accepted for disable-errors.", true)
			}
			if !confirm && !dryRun {
				return textResult("Error: disable-errors requires confirm=true or dry_run=true.", true)
			}
			if pluginsOnly {
				rest = append(rest, "--plugins-only")
			}
			if themesOnly {
				rest = append(rest, "--themes-only")
			}
			if confirm {
				rest = append(rest, "--yes")
			}
		}
		if dryRun && action != "show" && action != "plugins" && action != "themes" && action != "errors" {
			rest = append(rest, "--dry-run")
		}
		return RunCmd(FeatureArgv("config", rest...), false, DefaultTimeout)

	case "millennium_theme":
		action := stringArg(arguments, "action")
		theme := stringArg(arguments, "theme")
		allThemes := boolArg(arguments, "all")
		if theme != "" {
			if strings.Contains(theme, "..") || !themeRe.MatchString(theme) {
				return textResult("Error: theme name/URL contains invalid characters.", true)
			}
		}
		if !validThemeActions[action] {
			return textResult(
				fmt.Sprintf("Error: invalid action '%s'. Must be one of: %s.", action, sortedKeys(validThemeActions)),
				true,
			)
		}
		rest := []string{action}
		switch action {
		case "list":
			rest = append(rest, "--json")
		case "install", "remove":
			if theme == "" {
				return textResult("Error: theme name/URL is required for install/remove actions.", true)
			}
			rest = append(rest, theme)
		case "update":
			if allThemes {
				rest = append(rest, "--all")
			} else if theme != "" {
				rest = append(rest, theme)
			}
		}
		return RunCmd(FeatureArgv("theme", rest...), false, LongTimeout)

	case "millennium_upgrade":
		channel := stringArg(arguments, "channel")
		if channel == "" {
			channel = "stable"
		}
		force := boolArg(arguments, "force")
		rollback := stringArg(arguments, "rollback")
		if !validChannels[channel] {
			return textResult(
				fmt.Sprintf("Error: invalid channel '%s'. Must be one of: %s.", channel, sortedKeys(validChannels)),
				true,
			)
		}
		rest := []string{"--channel", channel}
		if force {
			rest = append(rest, "--force")
		}
		if rollback != "" {
			if rollback != "list" && !rollbackRe.MatchString(rollback) {
				return textResult("Error: invalid rollback target name format.", true)
			}
			rest = append(rest, "--rollback", rollback)
		}
		return RunCmd(FeatureArgv("upgrade", rest...), true, LongTimeout)

	case "millennium_schedule":
		action := stringArg(arguments, "action")
		channel := stringArg(arguments, "channel")
		cron := boolArg(arguments, "cron")
		system := boolArg(arguments, "system")
		user := boolArg(arguments, "user")
		if !validScheduleActions[action] {
			return textResult(
				fmt.Sprintf("Error: invalid action '%s'. Must be one of: %s.", action, sortedKeys(validScheduleActions)),
				true,
			)
		}
		if channel != "" && !validChannels[channel] {
			return textResult(
				fmt.Sprintf("Error: invalid channel '%s'. Must be one of: %s.", channel, sortedKeys(validChannels)),
				true,
			)
		}
		if system && user {
			return textResult("Error: cannot combine system=true and user=true.", true)
		}
		rest := []string{action}
		if action == "enable" && channel != "" {
			rest = append(rest, channel)
		}
		if cron {
			rest = append(rest, "--cron")
		}
		if system {
			rest = append(rest, "--system")
		}
		if user {
			rest = append(rest, "--user")
		}
		return RunCmd(FeatureArgv("schedule", rest...), false, DefaultTimeout)

	case "millennium_repair":
		return RunCmd(FeatureArgv("repair"), true, LongTimeout)

	case "millennium_purge":
		confirm := boolArg(arguments, "confirm")
		dryRun := boolArg(arguments, "dry_run")
		if !confirm && !dryRun {
			return textResult(
				"Error: millennium_purge requires confirm=true (or dry_run=true to simulate). This permanently removes Millennium.",
				true,
			)
		}
		var rest []string
		if dryRun {
			if runtime.GOOS == "windows" {
				rest = append(rest, "-DryRun")
			} else {
				rest = append(rest, "--dry-run")
			}
		} else if runtime.GOOS == "windows" {
			rest = append(rest, "-Yes")
		} else {
			rest = append(rest, "--yes")
		}
		return RunCmd(FeatureArgv("purge", rest...), true, LongTimeout)

	default:
		return textResult("Unknown tool: "+toolName, true)
	}
}
