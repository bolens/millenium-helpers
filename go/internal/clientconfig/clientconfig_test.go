package clientconfig

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
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

func TestMissingComponentDirectoriesAreEmpty(t *testing.T) {
	_, pluginsDir, themesDir := fixture(t)
	if err := os.RemoveAll(pluginsDir); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(themesDir); err != nil {
		t.Fatal(err)
	}
	plugins, err := Plugins()
	if err != nil || len(plugins) != 0 {
		t.Fatalf("plugins=%v err=%v", plugins, err)
	}
	themes, err := Themes()
	if err != nil || len(themes) != 0 {
		t.Fatalf("themes=%v err=%v", themes, err)
	}
}

func TestErrorsContinueWhenOneComponentDirectoryIsMissing(t *testing.T) {
	_, _, themesDir := fixture(t)
	if err := os.RemoveAll(themesDir); err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(t.TempDir(), "cef_log.txt")
	if err := os.WriteFile(logPath, []byte("Error: source /plugins/alpha/main.js\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_ERROR_LOG", logPath)
	findings, _, err := Errors()
	if err != nil || len(findings) != 1 || findings[0].Name != "alpha" {
		t.Fatalf("findings=%+v err=%v", findings, err)
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
	if runtime.GOOS != "windows" {
		info, err := os.Stat(configPath)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o640 {
			t.Fatalf("mode changed to %o", info.Mode().Perm())
		}
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
	for _, args := range [][]string{
		{"show", "--dry-run"},
		{"errors", "--quiet"},
		{"disable", "alpha", "--yes"},
	} {
		if _, err := ParseArgs(args); err == nil {
			t.Fatalf("expected invalid option combination for %v", args)
		}
	}
}

func TestUsageDocumentsErrorsJSON(t *testing.T) {
	if !strings.Contains(Usage(), "show/plugins/themes/errors") {
		t.Fatal("config help must document JSON output for errors")
	}
}

func TestCurrentSessionBoundary(t *testing.T) {
	data := []byte(`Error: old source /plugins/alpha/old.js
[2026-08-07 14:51:46] Startup - webhelper launched
Error: current source /plugins/beta/current.js
`)
	got := string(currentSession(data))
	if strings.Contains(got, "alpha") || !strings.Contains(got, "Startup - webhelper launched") || !strings.Contains(got, "beta") {
		t.Fatalf("unexpected current session: %q", got)
	}
	withoutMarker := []byte("Error: fallback /plugins/alpha/main.js\n")
	if got := currentSession(withoutMarker); !reflect.DeepEqual(got, withoutMarker) {
		t.Fatalf("markerless log changed: %q", got)
	}
}

func TestReadLogTailIsBoundedToCurrentSession(t *testing.T) {
	path := filepath.Join(t.TempDir(), "webhelper.txt")
	old := bytes.Repeat([]byte("Error: old /plugins/alpha/main.js\n"), maxErrorLogBytes/20)
	data := append(old, []byte("Startup - webhelper launched\nError: current /plugins/beta/main.js\n")...)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := readLogTail(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) > maxErrorLogBytes || bytes.Contains(got, []byte("/plugins/alpha/")) || !bytes.Contains(got, []byte("/plugins/beta/")) {
		t.Fatalf("unexpected bounded tail length=%d", len(got))
	}
}

func TestExistingLogPathsDeduplicatesSymlinks(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "webhelper.txt")
	alias := filepath.Join(dir, "cef_log.txt")
	if err := os.WriteFile(path, []byte("log"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(path, alias); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	got := existingLogPaths([]string{path, alias, path, filepath.Join(dir, "missing")})
	if !reflect.DeepEqual(got, []string{path}) {
		t.Fatalf("paths=%v", got)
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

func TestErrorsExcludePriorSessionAndSanitizeEvidence(t *testing.T) {
	fixture(t)
	logPath := filepath.Join(t.TempDir(), "webhelper.txt")
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	log := "Error: stale source /plugins/alpha/old.js\n" +
		"[2026-08-07 14:51:46] Startup - webhelper launched\n" +
		"Error: current source millennium.ftp" + home + "/plugins/beta/main.js\n"
	if err := os.WriteFile(logPath, []byte(log), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_ERROR_LOG", logPath)
	findings, _, err := Errors()
	if err != nil {
		t.Fatal(err)
	}
	if len(findings) != 1 || findings[0].Name != "beta" {
		t.Fatalf("unexpected findings: %+v", findings)
	}
	if strings.Contains(findings[0].Evidence, home) || !strings.Contains(findings[0].Evidence, "millennium.ftp/~") {
		t.Fatalf("evidence was not sanitized: %q", findings[0].Evidence)
	}
}

func TestErrorsAggregateMultipleLogsDeterministically(t *testing.T) {
	fixture(t)
	dir := t.TempDir()
	first := filepath.Join(dir, "cef_log.txt")
	second := filepath.Join(dir, "webhelper.txt")
	if err := os.WriteFile(first, []byte("Error: /plugins/beta/main.js\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(second, []byte("Error: /plugins/alpha/main.js\nError: /plugins/beta/again.js\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	findings, label, err := errorsFromPaths([]string{first, second})
	if err != nil {
		t.Fatal(err)
	}
	if label != "2 detected web logs" || len(findings) != 2 || findings[0].Name != "alpha" || findings[1].Name != "beta" || findings[1].Count != 2 {
		t.Fatalf("label=%q findings=%+v", label, findings)
	}
}

func TestDisableFlaggedIgnoresInactiveComponentsAndDryRun(t *testing.T) {
	configPath, _, _ := fixture(t)
	before, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	findings := []Finding{
		{Kind: "plugin", Name: "beta", Count: 1},
		{Kind: "theme", Name: "Demo", Count: 1},
		{Kind: "plugin", Name: "alpha", Enabled: true, Count: 1},
	}
	plugins, theme, err := DisableFlagged(findings, "all", true)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(plugins, []string{"alpha"}) || theme != "" {
		t.Fatalf("plugins=%v theme=%q", plugins, theme)
	}
	after, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(before, after) {
		t.Fatal("disable-errors dry-run changed config")
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
