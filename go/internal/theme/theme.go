package theme

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Info describes one installed theme.
type Info struct {
	Name   string `json:"name"`
	Owner  string `json:"owner,omitempty"`
	Repo   string `json:"repo,omitempty"`
	Commit string `json:"commit,omitempty"`
	Type   string `json:"type"`
	Active bool   `json:"active,omitempty"`
}

// SteamCandidates returns likely Steam roots for this OS.
func SteamCandidates() []string {
	home, _ := os.UserHomeDir()
	if runtime.GOOS == "windows" {
		var out []string
		for _, env := range []string{"STEAM", "STEAM_PATH"} {
			if v := os.Getenv(env); v != "" {
				out = append(out, v)
			}
		}
		if pf := os.Getenv("ProgramFiles(x86)"); pf != "" {
			out = append(out, filepath.Join(pf, "Steam"))
		}
		if pf := os.Getenv("ProgramFiles"); pf != "" {
			out = append(out, filepath.Join(pf, "Steam"))
		}
		return out
	}
	return []string{
		filepath.Join(home, ".local/share/Steam"),
		filepath.Join(home, ".steam/steam"),
		filepath.Join(home, ".steam/root"),
		filepath.Join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
		filepath.Join(home, "Library/Application Support/Steam"),
		os.Getenv("STEAM"),
	}
}

// FindSteamDir returns the first existing Steam root.
func FindSteamDir() string {
	for _, c := range SteamCandidates() {
		if c == "" {
			continue
		}
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			return c
		}
	}
	return ""
}

// SkinsDir returns steamui/skins under Steam, or override via MILLENNIUM_SKINS_DIR.
func SkinsDir() (string, error) {
	if d := os.Getenv("MILLENNIUM_SKINS_DIR"); d != "" {
		return d, nil
	}
	steam := FindSteamDir()
	if steam == "" {
		return "", fmt.Errorf("Error: No Steam directory detected on this system.")
	}
	return filepath.Join(steam, "steamui", "skins"), nil
}

// ActiveThemeName reads Millennium client config for the active skin name.
func ActiveThemeName() string {
	for _, cand := range activeConfigCandidates() {
		b, err := os.ReadFile(cand)
		if err != nil {
			continue
		}
		var data map[string]any
		if json.Unmarshal(b, &data) != nil {
			continue
		}
		themes, _ := data["themes"].(map[string]any)
		if themes == nil {
			continue
		}
		if name, ok := themes["activeTheme"].(string); ok && name != "" {
			return name
		}
	}
	return "Steam"
}

func activeConfigCandidates() []string {
	home, _ := os.UserHomeDir()
	var out []string
	if runtime.GOOS == "windows" {
		if app := os.Getenv("APPDATA"); app != "" {
			out = append(out, filepath.Join(app, "millennium", "config.json"))
		}
		if loc := os.Getenv("LOCALAPPDATA"); loc != "" {
			out = append(out, filepath.Join(loc, "millennium", "config.json"))
		}
	} else {
		xdg := os.Getenv("XDG_CONFIG_HOME")
		if xdg == "" {
			xdg = filepath.Join(home, ".config")
		}
		out = append(out,
			filepath.Join(xdg, "millennium", "config.json"),
			filepath.Join(home, ".config", "millennium", "config.json"),
			filepath.Join(home, ".var/app/com.valvesoftware.Steam/config/millennium/config.json"),
			filepath.Join(home, ".var/app/com.valvesoftware.Steam/.config/millennium/config.json"),
		)
	}
	if steam := FindSteamDir(); steam != "" {
		out = append(out,
			filepath.Join(steam, "millennium", "config.json"),
			filepath.Join(steam, "ext", "config.json"),
		)
	}
	return out
}

// ListInstalled returns themes under the skins directory.
func ListInstalled() ([]Info, string, error) {
	skins, err := SkinsDir()
	if err != nil {
		return nil, "", err
	}
	active := ActiveThemeName()
	entries, err := os.ReadDir(skins)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, skins, nil
		}
		return nil, skins, err
	}
	var out []Info
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info := Info{Name: e.Name(), Type: "local", Active: e.Name() == active}
		metaPath := filepath.Join(skins, e.Name(), "metadata.json")
		if b, err := os.ReadFile(metaPath); err == nil {
			var meta struct {
				Owner  string `json:"owner"`
				Repo   string `json:"repo"`
				Commit string `json:"commit"`
			}
			if json.Unmarshal(b, &meta) == nil && meta.Owner != "" && meta.Repo != "" {
				info.Owner = meta.Owner
				info.Repo = meta.Repo
				info.Commit = meta.Commit
				info.Type = "github"
			}
		}
		out = append(out, info)
	}
	return out, skins, nil
}

// FormatText prints the human list (colors omitted for portability).
func FormatText(themes []Info, skins string) string {
	var b strings.Builder
	b.WriteString("=== Installed Millennium Themes ===\n")
	if len(themes) == 0 {
		b.WriteString("No themes installed.\n")
		b.WriteString("Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin\n")
		_ = skins
		return b.String()
	}
	for _, t := range themes {
		flag := "[Installed]"
		if t.Active {
			flag = "[Active]   "
		}
		if t.Type == "github" {
			commit := t.Commit
			if len(commit) > 7 {
				commit = commit[:7]
			}
			b.WriteString(fmt.Sprintf("  %s  %-20s - %s/%s @ %s (GitHub)\n", flag, t.Name, t.Owner, t.Repo, commit))
		} else {
			b.WriteString(fmt.Sprintf("  %s  %-20s - Local / Manual Installation\n", flag, t.Name))
		}
	}
	return b.String()
}

// FormatJSON prints a JSON array (without active field — matches shell list JSON).
func FormatJSON(themes []Info) string {
	type row struct {
		Name   string `json:"name"`
		Owner  string `json:"owner,omitempty"`
		Repo   string `json:"repo,omitempty"`
		Commit string `json:"commit,omitempty"`
		Type   string `json:"type"`
	}
	rows := make([]row, 0, len(themes))
	for _, t := range themes {
		r := row{Name: t.Name, Type: t.Type}
		if t.Type == "github" {
			r.Owner = t.Owner
			r.Repo = t.Repo
			r.Commit = t.Commit
		}
		rows = append(rows, r)
	}
	b, err := json.Marshal(rows)
	if err != nil {
		return "[]"
	}
	return string(b)
}

// RunListCLI handles `theme list` args (--json / -Json, -q, --help).
func RunListCLI(args []string) int {
	asJSON := false
	for _, a := range args {
		switch a {
		case "--json", "-Json", "-json":
			asJSON = true
		case "-h", "--help", "-Help":
			fmt.Println("Usage: millennium theme list [--json]")
			return 0
		case "-q", "--quiet", "-Quiet", "-d", "--dry-run", "-DryRun", "-y", "--yes", "-Yes":
			// ignored for list
		default:
			if strings.HasPrefix(a, "-") {
				fmt.Fprintf(os.Stderr, "Error: unknown option %s\n", a)
				return 1
			}
		}
	}
	themes, skins, err := ListInstalled()
	if err != nil {
		if asJSON {
			fmt.Println("[]")
			return 0
		}
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	if asJSON {
		if themes == nil {
			fmt.Println("[]")
			return 0
		}
		// Missing skins dir: shell prints []
		if st, e := os.Stat(skins); e != nil || !st.IsDir() {
			fmt.Println("[]")
			return 0
		}
		fmt.Println(FormatJSON(themes))
		return 0
	}
	if st, e := os.Stat(skins); e != nil || !st.IsDir() {
		fmt.Printf("No themes skins directory found at %s.\n", skins)
		fmt.Println("Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin")
		return 0
	}
	if len(themes) == 0 {
		fmt.Println("=== Installed Millennium Themes ===")
		fmt.Println("No themes installed.")
		fmt.Println("Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin")
		return 0
	}
	fmt.Print(FormatText(themes, skins))
	return 0
}
