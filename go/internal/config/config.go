package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

// KnownKeys mirrors Bash/PowerShell schedule config.
var KnownKeys = []string{
	"update_channel",
	"github_token",
	"backup_limit",
	"backup_max_age_days",
}

// Data is the helpers config.json document.
type Data map[string]any

// Path returns the config.json path for the current OS/user.
func Path() string {
	if p := os.Getenv("MILLENNIUM_CONFIG_FILE"); p != "" {
		return p
	}
	dir := Dir()
	return filepath.Join(dir, "config.json")
}

// Dir returns the config directory (chmod 700 on Unix when created).
func Dir() string {
	if d := os.Getenv("MILLENNIUM_CONFIG_DIR"); d != "" {
		return d
	}
	if runtime.GOOS == "windows" {
		base := os.Getenv("LOCALAPPDATA")
		if base == "" {
			base = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
		}
		return filepath.Join(base, "millennium-helpers")
	}
	xdg := os.Getenv("XDG_CONFIG_HOME")
	if xdg == "" {
		home, _ := os.UserHomeDir()
		xdg = filepath.Join(home, ".config")
	}
	return filepath.Join(xdg, "millennium-helpers")
}

// Load reads config.json (empty map if missing/invalid).
func Load() (Data, error) {
	path := Path()
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return Data{}, nil
		}
		return nil, err
	}
	var data Data
	if err := json.Unmarshal(b, &data); err != nil {
		return Data{}, nil
	}
	if data == nil {
		data = Data{}
	}
	return data, nil
}

// Save writes config.json with indent and restrictive perms on Unix.
func Save(data Data) error {
	dir := Dir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	path := Path()
	if err := os.WriteFile(path, b, 0o600); err != nil {
		return err
	}
	_ = os.Chmod(path, 0o600)
	_ = os.Chmod(dir, 0o700)
	return nil
}

// ValidKey reports whether key is a known config key.
func ValidKey(key string) bool {
	for _, k := range KnownKeys {
		if k == key {
			return true
		}
	}
	return false
}

// Get returns the raw string form of a key (empty if unset).
func Get(data Data, key string) string {
	v, ok := data[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	case json.Number:
		return t.String()
	default:
		return fmt.Sprint(t)
	}
}

// Set validates and updates a key in data (does not save).
func Set(data Data, key, val string) error {
	if !ValidKey(key) {
		return fmt.Errorf("Error: Invalid config key '%s'. Valid keys: %s", key, strings.Join(KnownKeys, ", "))
	}
	switch key {
	case "update_channel":
		if val != "stable" && val != "beta" && val != "main" {
			return fmt.Errorf("Error: update_channel must be 'stable', 'beta', or 'main'.")
		}
		data[key] = val
	case "backup_limit":
		n, err := strconv.Atoi(val)
		if err != nil || n < 1 {
			return fmt.Errorf("Error: backup_limit must be a positive integer >= 1.")
		}
		data[key] = n
	case "backup_max_age_days":
		if val == "" {
			data[key] = nil
			return nil
		}
		n, err := strconv.Atoi(val)
		if err != nil || n < 0 {
			return fmt.Errorf("Error: backup_max_age_days must be a positive integer or empty.")
		}
		data[key] = n
	default:
		data[key] = val
	}
	return nil
}

// FormatList prints the human list format matching shell helpers.
func FormatList(data Data) string {
	var b strings.Builder
	b.WriteString("=== Millennium Helpers Configuration ===\n")
	for _, k := range KnownKeys {
		v, ok := data[k]
		valStr := "(not set)"
		if k == "github_token" && ok && v != nil && fmt.Sprint(v) != "" {
			s := fmt.Sprint(v)
			if len(s) >= 4 {
				valStr = s[:4] + "********"
			} else {
				valStr = "********"
			}
		} else if !ok || v == nil || fmt.Sprint(v) == "" {
			switch k {
			case "update_channel":
				valStr = "stable (default)"
			case "backup_limit":
				valStr = "5 (default)"
			default:
				valStr = "(not set)"
			}
		} else {
			valStr = Get(data, k)
		}
		b.WriteString(fmt.Sprintf("  %-20s : %s\n", k, valStr))
	}
	return b.String()
}

// RunCLI implements schedule config get|set|list (and show→list).
// Args are tokens after "config" (may include -d/--dry-run/-q/--quiet).
func RunCLI(args []string) int {
	dryRun := false
	quiet := false
	var positional []string
	for _, a := range args {
		switch a {
		case "-d", "--dry-run", "-DryRun":
			dryRun = true
		case "-q", "--quiet", "-Quiet":
			quiet = true
		case "-h", "--help", "-Help":
			fmt.Print(`Usage: millennium schedule config [list|get|set] [KEY] [VALUE]

Manage Millennium Helpers configuration (native Go).
`)
			return 0
		default:
			if strings.HasPrefix(a, "-") {
				fmt.Fprintf(os.Stderr, "Error: unknown option %s\n", a)
				return 1
			}
			positional = append(positional, a)
		}
	}

	action := "list"
	if len(positional) > 0 {
		action = positional[0]
	}
	key := ""
	val := ""
	if len(positional) > 1 {
		key = positional[1]
	}
	if len(positional) > 2 {
		val = positional[2]
	}

	data, err := Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to read configuration: %v\n", err)
		return 1
	}

	switch action {
	case "list", "show", "":
		fmt.Print(FormatList(data))
		return 0
	case "get":
		if key == "" {
			fmt.Fprintln(os.Stderr, "Error: config get requires a key name.")
			return 1
		}
		if !ValidKey(key) {
			fmt.Fprintf(os.Stderr, "Error: Invalid config key '%s'. Valid keys: %s\n", key, strings.Join(KnownKeys, ", "))
			return 1
		}
		fmt.Println(Get(data, key))
		return 0
	case "set":
		if key == "" {
			fmt.Fprintln(os.Stderr, "Error: config set requires a key name.")
			return 1
		}
		if err := Set(data, key, val); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			return 1
		}
		if dryRun {
			fmt.Fprintf(os.Stderr, "[DRY RUN] Would set config option %s to %s\n", key, val)
			return 0
		}
		if err := Save(data); err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to write configuration: %v\n", err)
			return 1
		}
		if !quiet {
			fmt.Printf("Config option %s set to '%s' successfully.\n", key, val)
		}
		return 0
	default:
		fmt.Fprintf(os.Stderr, "Error: Unknown config action '%s'. Use get, set, or list.\n", action)
		return 1
	}
}
