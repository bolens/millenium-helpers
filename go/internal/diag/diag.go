package diag

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/theme"
	"github.com/bolens/millenium-helpers/internal/version"
)

// Result is one read-only check line.
type Result struct {
	OK      bool
	Label   string
	Detail  string
}

// RunReadOnly performs non-elevating health checks (Phase 2 subset).
func RunReadOnly() []Result {
	var out []Result

	ver := version.Resolve()
	out = append(out, Result{OK: ver != "" && ver != "dev", Label: "Helpers Version", Detail: ver})
	if ver == "dev" {
		out[len(out)-1].OK = true // ok in checkout
		out[len(out)-1].Detail = ver + " (dev / unreleased)"
	}

	cfgPath := config.Path()
	data, err := config.Load()
	if err != nil {
		out = append(out, Result{OK: false, Label: "Helpers Config", Detail: err.Error()})
	} else if _, err := os.Stat(cfgPath); err != nil {
		out = append(out, Result{OK: true, Label: "Helpers Config", Detail: "not created yet (" + cfgPath + ")"})
	} else {
		ch := config.Get(data, "update_channel")
		if ch == "" {
			ch = "stable (default)"
		}
		out = append(out, Result{OK: true, Label: "Helpers Config", Detail: fmt.Sprintf("%s — channel %s", cfgPath, ch)})
	}

	steam := theme.FindSteamDir()
	if steam == "" {
		out = append(out, Result{OK: false, Label: "Steam Directory", Detail: "not found"})
	} else {
		out = append(out, Result{OK: true, Label: "Steam Directory", Detail: steam})
		skins := filepath.Join(steam, "steamui", "skins")
		if st, err := os.Stat(skins); err == nil && st.IsDir() {
			entries, _ := os.ReadDir(skins)
			n := 0
			for _, e := range entries {
				if e.IsDir() {
					n++
				}
			}
			out = append(out, Result{OK: true, Label: "Themes (skins)", Detail: fmt.Sprintf("%d installed under %s", n, skins)})
		} else {
			out = append(out, Result{OK: true, Label: "Themes (skins)", Detail: "skins directory not present yet"})
		}
	}

	out = append(out, Result{OK: true, Label: "Platform", Detail: runtime.GOOS + "/" + runtime.GOARCH})
	return out
}

// FormatReport renders a diag-style table.
func FormatReport(results []Result) string {
	var b strings.Builder
	b.WriteString("=== Millennium Helpers Diagnostics (native read-only) ===\n")
	b.WriteString("Note: hook/binary doctor checks still use the legacy diag via --fix / doctor.\n")
	for _, r := range results {
		mark := "[✔]"
		if !r.OK {
			mark = "[✘]"
		}
		b.WriteString(fmt.Sprintf("  %s %-40s : %s\n", mark, r.Label, r.Detail))
	}
	return b.String()
}

// NeedsLegacy reports whether args require the full Bash/PS diag.
func NeedsLegacy(args []string) bool {
	for _, a := range args {
		switch strings.ToLower(a) {
		case "doctor", "logs", "--fix", "-f", "-fix", "--force", "-force",
			"--json", "-json", "--share", "-s", "-share", "--follow", "-l", "-follow":
			return true
		}
	}
	return false
}

// RunCLI prints the native read-only report (exit 0 unless --help only).
func RunCLI(args []string) int {
	for _, a := range args {
		switch a {
		case "-h", "--help", "-Help":
			fmt.Print(`Usage: millennium diag [OPTIONS]

Native read-only summary (version, config, Steam/themes layout).
Use doctor / --fix / --json / --share for the full legacy diagnostic suite.
`)
			return 0
		}
	}
	fmt.Print(FormatReport(RunReadOnly()))
	return 0
}
