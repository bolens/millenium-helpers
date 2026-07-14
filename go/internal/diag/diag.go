package diag

import (
	"fmt"
	"os"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/theme"
	"github.com/bolens/millenium-helpers/internal/version"
)

// Result is one read-only check line (summary helper).
type Result struct {
	OK     bool
	Label  string
	Detail string
}

// RunReadOnly performs non-elevating health checks (summary subset).
func RunReadOnly() []Result {
	var out []Result

	ver := version.Resolve()
	detail := ver
	if ver == "dev" {
		detail = ver + " (dev / unreleased)"
	}
	out = append(out, Result{OK: true, Label: "Helpers Version", Detail: detail})

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

	rep := Collect()
	out = append(out, Result{OK: true, Label: "Steam Client", Detail: rep.SteamDetail})
	out = append(out, Result{OK: rep.BinariesOK, Label: "Millennium Binaries", Detail: rep.BinariesDetail})
	if steam := theme.FindSteamDir(); steam != "" {
		out = append(out, Result{OK: true, Label: "Steam Directory", Detail: steam})
	} else {
		out = append(out, Result{OK: false, Label: "Steam Directory", Detail: "not found"})
	}
	out = append(out, Result{OK: rep.SkinsDirOK, Label: "Themes (skins)", Detail: fmt.Sprintf("ok=%v", rep.SkinsDirOK)})
	return out
}

// FormatReport renders a diag-style table from Result rows.
func FormatReport(results []Result) string {
	var b strings.Builder
	b.WriteString("=== Millennium Helpers Diagnostics (native) ===\n")
	for _, r := range results {
		mark := "[✔]"
		if !r.OK {
			mark = "[✘]"
		}
		b.WriteString(fmt.Sprintf("  %s %-40s : %s\n", mark, r.Label, r.Detail))
	}
	return b.String()
}

// FormatReportFromCollect renders a fuller human report from Collect().
func FormatReportFromCollect(r Report) string {
	var b strings.Builder
	b.WriteString("=== Millennium Diagnostics Report ===\n\n")
	row := func(ok bool, label, detail string, warn bool) {
		mark := "[✔]"
		if warn {
			mark = "[!]"
		} else if !ok {
			mark = "[✘]"
		}
		b.WriteString(fmt.Sprintf("  %s %-40s : %s\n", mark, label, detail))
	}
	row(true, "Steam Client", r.SteamDetail, !r.SteamRunning)
	row(r.BinariesOK, "Millennium Binary Version", r.BinariesDetail, false)
	row(r.SkinsDirOK, "Skins Directory", fmt.Sprintf("present=%v", r.SkinsDirOK), false)
	schedOK := r.TimerActive || r.TaskScheduled
	if schedOK {
		row(true, "Scheduler", "configured", false)
	} else {
		row(false, "Scheduler", "not configured", false)
	}
	b.WriteString(fmt.Sprintf("\n  Update channel : %s\n", r.UpdateChannel))
	b.WriteString("\nTip: millennium diag --json for machine-readable output; doctor --dry-run for a repair plan.\n")
	return b.String()
}

// RunCLI runs native diag modes.
func RunCLI(args []string) int {
	o, err := ParseArgs(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	if o.Help {
		fmt.Print(`Usage: millennium diag [doctor|logs] [OPTIONS]

Native: default report, --json, logs (no --follow), doctor --dry-run.
Live doctor / --share / --follow still use legacy helpers.

  --json          Structured JSON report
  doctor|--fix   Auto-repair (live → legacy; --dry-run native)
  logs            Recent updater + Steam WebHelper lines
  -d, --dry-run   Simulate doctor plan
  -h, --help
`)
		return 0
	}
	if o.Logs {
		return PrintLogs()
	}
	rep := Collect()
	if o.JSON {
		fmt.Print(FormatJSON(rep))
		return 0
	}
	if o.Doctor && o.DryRun {
		fmt.Print(FormatDoctorDryRun(rep, o.Force))
		return 0
	}
	fmt.Print(FormatReportFromCollect(rep))
	return 0
}
