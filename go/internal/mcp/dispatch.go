package mcp

import (
	"fmt"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

var (
	validThemeActions    = map[string]bool{"list": true, "install": true, "remove": true, "update": true}
	validScheduleActions = map[string]bool{"enable": true, "disable": true, "status": true}
	validChannels        = map[string]bool{"stable": true, "beta": true, "main": true}
	themeRe              = regexp.MustCompile(`^[a-zA-Z0-9_\-\./:]+$`)
	rollbackRe           = regexp.MustCompile(`^[a-zA-Z0-9_\-\.]+$`)
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
