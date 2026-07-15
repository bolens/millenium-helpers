//go:build windows

package install

import (
	"os"
	"path/filepath"
)

func installWindowsExtras(o Options, dispatcher string, res *Result) error {
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

	// Optional cmd.exe shim (no long-name PATH twins).
	cmdPath := filepath.Join(o.TargetDir, "millennium.cmd")
	body := "@echo off\r\n\"%~dp0millennium.exe\" %*\r\n"
	res.Plan = append(res.Plan, "write "+cmdPath)
	if !o.DryRun {
		if err := os.WriteFile(cmdPath, []byte(body), 0o644); err != nil {
			return err
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
