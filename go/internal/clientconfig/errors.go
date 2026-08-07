package clientconfig

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"github.com/bolens/millenium-helpers/internal/steam"
)

const maxErrorLogBytes = 4 << 20

// Finding is a directly attributed recent plugin or theme error.
type Finding struct {
	Kind     string `json:"kind"`
	Name     string `json:"name"`
	Count    int    `json:"count"`
	Enabled  bool   `json:"enabled,omitempty"`
	Active   bool   `json:"active,omitempty"`
	Evidence string `json:"evidence"`
}

func errorLogPaths() []string {
	if path := os.Getenv("MILLENNIUM_ERROR_LOG"); path != "" {
		return []string{path}
	}
	var candidates []string
	for _, root := range steam.DirCandidates() {
		if root == "" {
			continue
		}
		candidates = append(candidates,
			filepath.Join(root, "logs", "cef_log.txt"),
			filepath.Join(root, "logs", "webhelper.txt"),
			filepath.Join(root, "logs", "webhelper-linux.txt"),
			filepath.Join(root, "config", "htmlcache", "chrome_debug.log"),
		)
	}
	if runtime.GOOS == "windows" {
		for _, base := range []string{os.Getenv("APPDATA"), os.Getenv("LOCALAPPDATA")} {
			if base != "" {
				candidates = append(candidates, filepath.Join(base, "millennium", "logs", "cef_log.txt"))
			}
		}
	}
	return existingLogPaths(candidates)
}

func existingLogPaths(candidates []string) []string {
	var existing []string
	seen := make(map[string]bool)
	for _, path := range candidates {
		canonical := path
		if resolved, err := filepath.EvalSymlinks(path); err == nil {
			canonical = resolved
		}
		if seen[canonical] {
			continue
		}
		seen[canonical] = true
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
			existing = append(existing, path)
		}
	}
	return existing
}

func readLogTail(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	start := info.Size() - maxErrorLogBytes
	if start < 0 {
		start = 0
	}
	if _, err := file.Seek(start, 0); err != nil {
		return nil, err
	}
	data, err := io.ReadAll(io.LimitReader(file, maxErrorLogBytes))
	if err != nil {
		return nil, err
	}
	return currentSession(data), nil
}

func currentSession(data []byte) []byte {
	start := -1
	offset := 0
	for _, line := range strings.SplitAfter(string(data), "\n") {
		lower := strings.ToLower(line)
		if strings.Contains(lower, "startup - webhelper launched") ||
			strings.Contains(lower, "this is chrome version") ||
			(strings.Contains(lower, "srt-logger") && strings.Contains(lower, "log opened")) {
			start = offset
		}
		offset += len(line)
	}
	if start < 0 {
		return data
	}
	return data[start:]
}

func errorSourceLabel(paths []string) string {
	if len(paths) == 1 {
		return paths[0]
	}
	return fmt.Sprintf("%d detected web logs", len(paths))
}

func errorIndicator(line string) bool {
	line = strings.ToLower(line)
	for _, marker := range []string{"uncaught", "exception", "error", "failed", "could not", "refused to load"} {
		if strings.Contains(line, marker) {
			return true
		}
	}
	return false
}

func sanitizeEvidence(line string) string {
	line = strings.TrimSpace(line)
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		line = strings.ReplaceAll(line, "millennium.ftp"+home, "millennium.ftp/~")
		line = strings.ReplaceAll(line, home, "~")
	}
	if len(line) > 300 {
		line = line[:300] + "..."
	}
	return line
}

// Errors scans the current session in Steam/Millennium web logs for direct component source paths.
func Errors() ([]Finding, string, error) {
	paths := errorLogPaths()
	if len(paths) == 0 {
		return nil, "", fmt.Errorf("no Steam or Millennium web log found")
	}
	return errorsFromPaths(paths)
}

func errorsFromPaths(paths []string) ([]Finding, string, error) {
	plugins, err := Plugins()
	if err != nil {
		return nil, errorSourceLabel(paths), err
	}
	themes, err := Themes()
	if err != nil {
		return nil, errorSourceLabel(paths), err
	}
	findings := make(map[string]Finding)
	for _, path := range paths {
		data, readErr := readLogTail(path)
		if readErr != nil {
			return nil, errorSourceLabel(paths), readErr
		}
		lines := strings.Split(strings.ReplaceAll(string(data), "\\", "/"), "\n")
		for _, line := range lines {
			if !errorIndicator(line) {
				continue
			}
			lower := strings.ToLower(line)
			for _, plugin := range plugins {
				if strings.Contains(lower, "/plugins/"+strings.ToLower(plugin.Name)+"/") {
					key := "plugin\x00" + plugin.Name
					finding := findings[key]
					finding.Kind, finding.Name, finding.Enabled = "plugin", plugin.Name, plugin.Enabled
					finding.Count++
					finding.Evidence = sanitizeEvidence(line)
					findings[key] = finding
				}
			}
			for _, theme := range themes {
				if strings.Contains(lower, "/themes/"+strings.ToLower(theme.Name)+"/") {
					key := "theme\x00" + theme.Name
					finding := findings[key]
					finding.Kind, finding.Name, finding.Active = "theme", theme.Name, theme.Active
					finding.Count++
					finding.Evidence = sanitizeEvidence(line)
					findings[key] = finding
				}
			}
		}
	}
	result := make([]Finding, 0, len(findings))
	for _, finding := range findings {
		result = append(result, finding)
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Kind != result[j].Kind {
			return result[i].Kind < result[j].Kind
		}
		return result[i].Name < result[j].Name
	})
	return result, errorSourceLabel(paths), nil
}

// DisableTheme resets the active theme to Steam, optionally guarding its current name.
func DisableTheme(expected string, dryRun bool) error {
	summary, err := Show()
	if err != nil {
		return err
	}
	if expected != "" && summary.ActiveTheme != expected {
		return fmt.Errorf("theme %q is not active (active theme: %q)", expected, summary.ActiveTheme)
	}
	if summary.ActiveTheme == "Steam" {
		return nil
	}
	return SetTheme("Steam", dryRun)
}

// DisableFlagged disables enabled plugins and the active non-Steam theme with findings.
func DisableFlagged(findings []Finding, scope string, dryRun bool) (plugins []string, theme string, err error) {
	if scope != "all" && scope != "plugins" && scope != "themes" {
		return nil, "", fmt.Errorf("invalid disable scope %q", scope)
	}
	for _, finding := range findings {
		if finding.Kind == "plugin" && finding.Enabled && scope != "themes" {
			plugins = append(plugins, finding.Name)
		}
		if finding.Kind == "theme" && finding.Active && finding.Name != "Steam" && scope != "plugins" {
			theme = finding.Name
		}
	}
	if len(plugins) == 0 && theme == "" {
		return plugins, theme, nil
	}
	data, err := load()
	if err != nil {
		return plugins, theme, err
	}
	pluginConfig, err := object(data, "plugins")
	if err != nil {
		return plugins, theme, err
	}
	current, err := stringsField(pluginConfig, "enabledPlugins")
	if err != nil {
		return plugins, theme, err
	}
	disable := make(map[string]bool, len(plugins))
	for _, name := range plugins {
		disable[name] = true
	}
	next := make([]string, 0, len(current))
	for _, name := range current {
		if !disable[name] {
			next = append(next, name)
		}
	}
	pluginConfig["enabledPlugins"] = next
	if theme != "" {
		themeConfig, objectErr := object(data, "themes")
		if objectErr != nil {
			return plugins, theme, objectErr
		}
		themeConfig["activeTheme"] = "Steam"
	}
	if dryRun {
		return plugins, theme, nil
	}
	return plugins, theme, save(data)
}
