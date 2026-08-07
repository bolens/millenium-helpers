// Package clientconfig manages the Millennium client's own settings.
package clientconfig

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"github.com/bolens/millenium-helpers/internal/atomicfile"
	"github.com/bolens/millenium-helpers/internal/steam"
)

// Summary contains the safe, user-facing subset of Millennium client settings.
type Summary struct {
	ActiveTheme                   string   `json:"activeTheme"`
	MillenniumUpdateChannel       string   `json:"millenniumUpdateChannel"`
	CheckForMillenniumUpdates     bool     `json:"checkForMillenniumUpdates"`
	CheckForPluginAndThemeUpdates bool     `json:"checkForPluginAndThemeUpdates"`
	EnabledPlugins                []string `json:"enabledPlugins"`
}

// Plugin describes an installed plugin and its enabled state.
type Plugin struct {
	Name    string `json:"name"`
	Enabled bool   `json:"enabled"`
}

// Theme describes an installed client theme and its active state.
type Theme struct {
	Name   string `json:"name"`
	Active bool   `json:"active"`
}

type document map[string]any

func existingOrFirst(candidates []string) string {
	seen := make(map[string]bool)
	first := ""
	for _, path := range candidates {
		if path == "" || seen[path] {
			continue
		}
		seen[path] = true
		if first == "" {
			first = path
		}
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return first
}

// Path locates Millennium's client config, preferring existing native and sandbox paths.
func Path() string {
	if path := os.Getenv("MILLENNIUM_CLIENT_CONFIG_FILE"); path != "" {
		return path
	}
	home, _ := os.UserHomeDir()
	var candidates []string
	if runtime.GOOS == "windows" {
		for _, base := range []string{os.Getenv("APPDATA"), os.Getenv("LOCALAPPDATA")} {
			if base != "" {
				candidates = append(candidates, filepath.Join(base, "millennium", "config.json"))
			}
		}
	} else {
		xdg := os.Getenv("XDG_CONFIG_HOME")
		if xdg == "" {
			xdg = filepath.Join(home, ".config")
		}
		candidates = append(candidates,
			filepath.Join(xdg, "millennium", "config.json"),
			filepath.Join(home, ".config", "millennium", "config.json"),
			filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", "config", "millennium", "config.json"),
			filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", ".config", "millennium", "config.json"),
		)
	}
	if root := steam.FindDir(); root != "" {
		candidates = append(candidates,
			filepath.Join(root, "millennium", "config.json"),
			filepath.Join(root, "ext", "config.json"),
		)
	}
	return existingOrFirst(candidates)
}

// PluginsDir locates the installed Millennium plugins directory.
func PluginsDir() string {
	if path := os.Getenv("MILLENNIUM_PLUGINS_DIR"); path != "" {
		return path
	}
	home, _ := os.UserHomeDir()
	var candidates []string
	if runtime.GOOS == "windows" {
		for _, base := range []string{os.Getenv("APPDATA"), os.Getenv("LOCALAPPDATA")} {
			if base != "" {
				candidates = append(candidates, filepath.Join(base, "millennium", "plugins"))
			}
		}
	} else {
		data := os.Getenv("XDG_DATA_HOME")
		if data == "" {
			data = filepath.Join(home, ".local", "share")
		}
		candidates = append(candidates,
			filepath.Join(data, "millennium", "plugins"),
			filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", "data", "millennium", "plugins"),
		)
	}
	if root := steam.FindDir(); root != "" {
		candidates = append(candidates, filepath.Join(root, "millennium", "plugins"))
	}
	return existingOrFirst(candidates)
}

// ThemesDir locates Millennium's installed client themes directory.
func ThemesDir() string {
	if path := os.Getenv("MILLENNIUM_CLIENT_THEMES_DIR"); path != "" {
		return path
	}
	home, _ := os.UserHomeDir()
	var candidates []string
	if root := steam.FindDir(); root != "" {
		candidates = append(candidates, filepath.Join(root, "millennium", "themes"))
	}
	if runtime.GOOS == "windows" {
		for _, base := range []string{os.Getenv("APPDATA"), os.Getenv("LOCALAPPDATA")} {
			if base != "" {
				candidates = append(candidates, filepath.Join(base, "millennium", "themes"))
			}
		}
	} else {
		data := os.Getenv("XDG_DATA_HOME")
		if data == "" {
			data = filepath.Join(home, ".local", "share")
		}
		candidates = append(candidates,
			filepath.Join(data, "millennium", "themes"),
			filepath.Join(home, ".var", "app", "com.valvesoftware.Steam", "data", "millennium", "themes"),
		)
	}
	return existingOrFirst(candidates)
}

func load() (document, error) {
	path := Path()
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("could not read Millennium client config at %s: %w", path, err)
	}
	var data document
	if err := json.Unmarshal(b, &data); err != nil {
		return nil, fmt.Errorf("invalid Millennium client config at %s: %w", path, err)
	}
	return data, nil
}

func object(data document, key string) (map[string]any, error) {
	value, ok := data[key]
	if !ok {
		value = map[string]any{}
		data[key] = value
	}
	result, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Millennium client config field %q is not an object", key)
	}
	return result, nil
}

func stringsField(parent map[string]any, key string) ([]string, error) {
	value, ok := parent[key]
	if !ok {
		return []string{}, nil
	}
	values, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("Millennium client config field %q is not an array", key)
	}
	result := make([]string, 0, len(values))
	for _, value := range values {
		text, ok := value.(string)
		if !ok {
			return nil, fmt.Errorf("Millennium client config field %q contains a non-string value", key)
		}
		result = append(result, text)
	}
	return result, nil
}

func stringValue(parent map[string]any, key string) string {
	value, _ := parent[key].(string)
	return value
}

func boolValue(parent map[string]any, key string) bool {
	value, _ := parent[key].(bool)
	return value
}

// Show returns the safe client configuration summary.
func Show() (Summary, error) {
	data, err := load()
	if err != nil {
		return Summary{}, err
	}
	general, err := object(data, "general")
	if err != nil {
		return Summary{}, err
	}
	plugins, err := object(data, "plugins")
	if err != nil {
		return Summary{}, err
	}
	themes, err := object(data, "themes")
	if err != nil {
		return Summary{}, err
	}
	enabled, err := stringsField(plugins, "enabledPlugins")
	if err != nil {
		return Summary{}, err
	}
	sort.Strings(enabled)
	return Summary{
		ActiveTheme:                   stringValue(themes, "activeTheme"),
		MillenniumUpdateChannel:       stringValue(general, "millenniumUpdateChannel"),
		CheckForMillenniumUpdates:     boolValue(general, "checkForMillenniumUpdates"),
		CheckForPluginAndThemeUpdates: boolValue(general, "checkForPluginAndThemeUpdates"),
		EnabledPlugins:                enabled,
	}, nil
}

func directories(path string) ([]string, error) {
	entries, err := os.ReadDir(path)
	if os.IsNotExist(err) {
		return []string{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("could not read %s: %w", path, err)
	}
	result := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			result = append(result, entry.Name())
		}
	}
	sort.Strings(result)
	return result, nil
}

// Plugins lists installed plugins and their enabled state.
func Plugins() ([]Plugin, error) {
	summary, err := Show()
	if err != nil {
		return nil, err
	}
	names, err := directories(PluginsDir())
	if err != nil {
		return nil, err
	}
	enabled := make(map[string]bool, len(summary.EnabledPlugins))
	for _, name := range summary.EnabledPlugins {
		enabled[name] = true
	}
	result := make([]Plugin, 0, len(names))
	for _, name := range names {
		result = append(result, Plugin{Name: name, Enabled: enabled[name]})
	}
	return result, nil
}

// Themes lists installed client themes and their active state.
func Themes() ([]Theme, error) {
	summary, err := Show()
	if err != nil {
		return nil, err
	}
	names, err := directories(ThemesDir())
	if err != nil {
		return nil, err
	}
	result := make([]Theme, 0, len(names))
	for _, name := range names {
		result = append(result, Theme{Name: name, Active: name == summary.ActiveTheme})
	}
	return result, nil
}

func validateNames(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("at least one name is required")
	}
	for _, name := range names {
		if name == "" || name == "." || name == ".." || strings.ContainsAny(name, `/\\`) {
			return fmt.Errorf("invalid plugin or theme name %q", name)
		}
	}
	return nil
}

func save(data document) error {
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	path := Path()
	mode := os.FileMode(0o600)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	return atomicfile.WriteFile(path, b, mode)
}

// SetPlugins enables or disables installed plugins and atomically saves the config.
func SetPlugins(names []string, enable, dryRun bool) error {
	if err := validateNames(names); err != nil {
		return err
	}
	if enable {
		for _, name := range names {
			if info, err := os.Stat(filepath.Join(PluginsDir(), name)); err != nil || !info.IsDir() {
				return fmt.Errorf("unknown plugin %q", name)
			}
		}
	}
	data, err := load()
	if err != nil {
		return err
	}
	plugins, err := object(data, "plugins")
	if err != nil {
		return err
	}
	current, err := stringsField(plugins, "enabledPlugins")
	if err != nil {
		return err
	}
	set := make(map[string]bool, len(current)+len(names))
	for _, name := range current {
		set[name] = true
	}
	for _, name := range names {
		if enable {
			set[name] = true
		} else {
			delete(set, name)
		}
	}
	next := make([]string, 0, len(set))
	for name := range set {
		next = append(next, name)
	}
	sort.Strings(next)
	plugins["enabledPlugins"] = next
	if dryRun {
		return nil
	}
	return save(data)
}

// SetTheme selects an installed client theme and atomically saves the config.
func SetTheme(name string, dryRun bool) error {
	if err := validateNames([]string{name}); err != nil {
		return err
	}
	if info, err := os.Stat(filepath.Join(ThemesDir(), name)); err != nil || !info.IsDir() {
		return fmt.Errorf("unknown theme %q", name)
	}
	data, err := load()
	if err != nil {
		return err
	}
	themes, err := object(data, "themes")
	if err != nil {
		return err
	}
	themes["activeTheme"] = name
	if dryRun {
		return nil
	}
	return save(data)
}
