package clientconfig

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func fixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	configPath := filepath.Join(root, "config.json")
	plugins := filepath.Join(root, "plugins")
	themes := filepath.Join(root, "themes")
	for _, path := range []string{
		filepath.Join(plugins, "alpha"),
		filepath.Join(plugins, "beta"),
		filepath.Join(themes, "Steam"),
		filepath.Join(themes, "Demo"),
	} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	data := `{
  "general": {
    "millenniumUpdateChannel": "beta",
    "checkForMillenniumUpdates": true,
    "checkForPluginAndThemeUpdates": false,
    "unknownGeneral": 42
  },
  "plugins": {"enabledPlugins": ["alpha"]},
  "themes": {"activeTheme": "Steam", "themeColors": {"accent": "purple"}},
  "unknownTopLevel": {"preserve": true}
}
`
	if err := os.WriteFile(configPath, []byte(data), 0o640); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_CLIENT_CONFIG_FILE", configPath)
	t.Setenv("MILLENNIUM_PLUGINS_DIR", plugins)
	t.Setenv("MILLENNIUM_CLIENT_THEMES_DIR", themes)
	return configPath, plugins, themes
}

func TestShowPluginsAndThemes(t *testing.T) {
	fixture(t)
	summary, err := Show()
	if err != nil {
		t.Fatal(err)
	}
	if summary.ActiveTheme != "Steam" || summary.MillenniumUpdateChannel != "beta" ||
		!summary.CheckForMillenniumUpdates || summary.CheckForPluginAndThemeUpdates ||
		!reflect.DeepEqual(summary.EnabledPlugins, []string{"alpha"}) {
		t.Fatalf("unexpected summary: %+v", summary)
	}
	plugins, err := Plugins()
	if err != nil {
		t.Fatal(err)
	}
	if len(plugins) != 2 || plugins[0] != (Plugin{Name: "alpha", Enabled: true}) || plugins[1].Name != "beta" {
		t.Fatalf("unexpected plugins: %+v", plugins)
	}
	themes, err := Themes()
	if err != nil {
		t.Fatal(err)
	}
	if len(themes) != 2 || themes[0].Name != "Demo" || themes[1] != (Theme{Name: "Steam", Active: true}) {
		t.Fatalf("unexpected themes: %+v", themes)
	}
}

func TestMutationsPreserveUnknownFieldsAndMode(t *testing.T) {
	configPath, _, _ := fixture(t)
	if err := SetPlugins([]string{"beta"}, true, false); err != nil {
		t.Fatal(err)
	}
	if err := SetPlugins([]string{"alpha"}, false, false); err != nil {
		t.Fatal(err)
	}
	if err := SetTheme("Demo", false); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	var data map[string]any
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	plugins := data["plugins"].(map[string]any)["enabledPlugins"].([]any)
	if !reflect.DeepEqual(plugins, []any{"beta"}) {
		t.Fatalf("enabled plugins: %#v", plugins)
	}
	if data["unknownTopLevel"].(map[string]any)["preserve"] != true {
		t.Fatal("unknown top-level data was not preserved")
	}
	if data["general"].(map[string]any)["unknownGeneral"] != float64(42) {
		t.Fatal("unknown nested data was not preserved")
	}
	if data["themes"].(map[string]any)["activeTheme"] != "Demo" {
		t.Fatal("active theme was not changed")
	}
	info, err := os.Stat(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o640 {
		t.Fatalf("mode changed to %o", info.Mode().Perm())
	}
}

func TestDryRunAndValidation(t *testing.T) {
	configPath, _, _ := fixture(t)
	before, _ := os.ReadFile(configPath)
	if err := SetPlugins([]string{"beta"}, true, true); err != nil {
		t.Fatal(err)
	}
	if err := SetTheme("Demo", true); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(configPath)
	if !reflect.DeepEqual(before, after) {
		t.Fatal("dry-run changed config")
	}
	if err := SetPlugins([]string{"missing"}, true, false); err == nil {
		t.Fatal("expected unknown plugin error")
	}
	if err := SetTheme("../Demo", false); err == nil {
		t.Fatal("expected unsafe theme name error")
	}
}

func TestParseArgs(t *testing.T) {
	options, err := ParseArgs([]string{"--dry-run", "enable", "alpha", "beta"})
	if err != nil || options.Action != "enable" || !options.DryRun || !reflect.DeepEqual(options.Names, []string{"alpha", "beta"}) {
		t.Fatalf("options=%+v err=%v", options, err)
	}
	if _, err := ParseArgs([]string{"show", "extra"}); err == nil {
		t.Fatal("expected extra argument error")
	}
	if _, err := ParseArgs([]string{"enable", "alpha", "--json"}); err == nil {
		t.Fatal("expected invalid json mutation error")
	}
	if _, err := ParseArgs([]string{"disable-errors"}); err == nil {
		t.Fatal("expected disable-errors confirmation error")
	}
	if options, err := ParseArgs([]string{"disable-errors", "--yes"}); err != nil || !options.Yes {
		t.Fatalf("disable-errors options=%+v err=%v", options, err)
	}
	if options, err := ParseArgs([]string{"disable-errors", "--plugins-only", "--dry-run"}); err != nil || !options.PluginsOnly {
		t.Fatalf("plugins-only options=%+v err=%v", options, err)
	}
	if _, err := ParseArgs([]string{"disable-errors", "--plugins-only", "--themes-only", "--dry-run"}); err == nil {
		t.Fatal("expected conflicting scope error")
	}
	if _, err := ParseArgs([]string{"plugins", "--plugins-only"}); err == nil {
		t.Fatal("expected scoped flag action error")
	}
}

func TestErrorAttributionAndDisableFlagged(t *testing.T) {
	configPath, _, _ := fixture(t)
	if err := SetPlugins([]string{"beta"}, true, false); err != nil {
		t.Fatal(err)
	}
	if err := SetTheme("Demo", false); err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(t.TempDir(), "cef_log.txt")
	log := `Uncaught TypeError: boom, source: https://millennium.ftp/home/user/plugins/beta/dist.js
Error: theme failed, source: https://millennium.host/v1/themes/Demo/main.js
Error mentioning alpha without a direct component source path
ordinary source: https://millennium.ftp/home/user/plugins/alpha/dist.js
`
	if err := os.WriteFile(logPath, []byte(log), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_ERROR_LOG", logPath)
	findings, gotPath, err := Errors()
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != logPath || len(findings) != 2 {
		t.Fatalf("path=%q findings=%+v", gotPath, findings)
	}
	plugins, theme, err := DisableFlagged(findings, "all", false)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(plugins, []string{"beta"}) || theme != "Demo" {
		t.Fatalf("plugins=%v theme=%q", plugins, theme)
	}
	b, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	var data map[string]any
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if data["themes"].(map[string]any)["activeTheme"] != "Steam" {
		t.Fatal("flagged active theme was not reset")
	}
	enabled := data["plugins"].(map[string]any)["enabledPlugins"].([]any)
	if !reflect.DeepEqual(enabled, []any{"alpha"}) {
		t.Fatalf("unexpected enabled plugins: %#v", enabled)
	}
}

func TestDisableFlaggedScopes(t *testing.T) {
	for _, test := range []struct {
		name         string
		scope        string
		wantPlugins  []string
		wantTheme    string
		enabledAfter []any
		activeAfter  string
	}{
		{name: "all", scope: "all", wantPlugins: []string{"alpha"}, wantTheme: "Demo", enabledAfter: []any{}, activeAfter: "Steam"},
		{name: "plugins only", scope: "plugins", wantPlugins: []string{"alpha"}, enabledAfter: []any{}, activeAfter: "Demo"},
		{name: "themes only", scope: "themes", wantTheme: "Demo", enabledAfter: []any{"alpha"}, activeAfter: "Steam"},
	} {
		t.Run(test.name, func(t *testing.T) {
			configPath, _, _ := fixture(t)
			if err := SetTheme("Demo", false); err != nil {
				t.Fatal(err)
			}
			findings := []Finding{
				{Kind: "plugin", Name: "alpha", Enabled: true, Count: 2},
				{Kind: "theme", Name: "Demo", Active: true, Count: 1},
			}
			plugins, theme, err := DisableFlagged(findings, test.scope, false)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(plugins, test.wantPlugins) || theme != test.wantTheme {
				t.Fatalf("plugins=%v theme=%q", plugins, theme)
			}
			b, err := os.ReadFile(configPath)
			if err != nil {
				t.Fatal(err)
			}
			var data map[string]any
			if err := json.Unmarshal(b, &data); err != nil {
				t.Fatal(err)
			}
			if got := data["plugins"].(map[string]any)["enabledPlugins"].([]any); !reflect.DeepEqual(got, test.enabledAfter) {
				t.Fatalf("enabled=%v want=%v", got, test.enabledAfter)
			}
			if got := data["themes"].(map[string]any)["activeTheme"]; got != test.activeAfter {
				t.Fatalf("active=%v want=%v", got, test.activeAfter)
			}
		})
	}
	if _, _, err := DisableFlagged(nil, "bogus", true); err == nil {
		t.Fatal("expected invalid scope error")
	}
}
