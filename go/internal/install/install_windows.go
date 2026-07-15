//go:build windows

package install

import (
	"fmt"
	"os"
	"path/filepath"
)

func installWindowsExtras(o Options, dispatcher string, res *Result) error {
	srcDir := filepath.Join(o.SourceRoot, "scripts", "windows")
	common := filepath.Join(srcDir, "common.ps1")
	if _, err := os.Stat(common); err == nil {
		if err := planCopy(common, filepath.Join(o.TargetDir, "common.ps1"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	libSrc := filepath.Join(srcDir, "lib")
	libDst := filepath.Join(o.TargetDir, "lib")
	if st, err := os.Stat(libSrc); err == nil && st.IsDir() {
		if err := ensureDir(libDst, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if o.DryRun {
			res.Plan = append(res.Plan, "install scripts/windows/lib/*.ps1 → "+libDst)
		} else if err := copyTreeFiles(libSrc, libDst, "*.ps1"); err != nil {
			return err
		}
	}
	verSrc := filepath.Join(o.SourceRoot, "VERSION")
	if _, err := os.Stat(verSrc); err == nil {
		if err := planCopy(verSrc, filepath.Join(o.TargetDir, "VERSION"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	lic := filepath.Join(o.SourceRoot, "third_party", "MILLENNIUM-LICENSE.md")
	if _, err := os.Stat(lic); err == nil {
		if err := planCopy(lic, filepath.Join(o.TargetDir, "MILLENNIUM-LICENSE.md"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}

	cmdMap := map[string]string{
		"millennium":          "",
		"millennium-mcp":      "mcp",
		"millennium-diag":     "diag",
		"millennium-purge":    "purge",
		"millennium-repair":   "repair",
		"millennium-schedule": "schedule",
		"millennium-theme":    "theme",
		"millennium-upgrade":  "upgrade",
	}
	for name, sub := range cmdMap {
		path := filepath.Join(o.TargetDir, name+".cmd")
		var body string
		if sub == "" {
			body = "@echo off\r\n\"%~dp0millennium.exe\" %*\r\n"
		} else {
			body = fmt.Sprintf("@echo off\r\n\"%%~dp0millennium.exe\" %s %%*\r\n", sub)
		}
		res.Plan = append(res.Plan, "write "+path)
		if !o.DryRun {
			if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
				return err
			}
		}
	}

	compSrc := filepath.Join(o.SourceRoot, "completions", "powershell", "millennium-helpers.ps1")
	if _, err := os.Stat(compSrc); err == nil {
		if err := planCopy(compSrc, filepath.Join(o.TargetDir, "millennium-helpers.completion.ps1"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	_ = dispatcher
	return nil
}

func installUnixCompletionsAndMan(Options, string, *Result) error { return nil }
func removeUnixCompletionsAndMan(Options, *Result)                 {}
