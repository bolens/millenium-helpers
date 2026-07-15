//go:build windows

package install

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func installWindowsCompletionHooks(o Options, res *Result) error {
	comp := filepath.Join(o.TargetDir, "millennium-helpers.completion.ps1")
	if _, err := os.Stat(comp); err != nil && !o.DryRun {
		return nil
	}
	home := os.Getenv("USERPROFILE")
	if home == "" {
		home, _ = os.UserHomeDir()
	}
	profiles := []string{
		filepath.Join(home, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"),
		filepath.Join(home, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"),
	}
	hook := fmt.Sprintf(". %q", comp)
	for _, profilePath := range profiles {
		res.Plan = append(res.Plan, "register completion hook "+profilePath)
		if o.DryRun {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(profilePath), 0o755); err != nil {
			return err
		}
		existing := ""
		if b, err := os.ReadFile(profilePath); err == nil {
			existing = string(b)
		}
		if strings.Contains(existing, "millennium-helpers.completion.ps1") {
			continue
		}
		block := "\n# Millennium Helpers completions\n" + hook + "\n"
		f, err := os.OpenFile(profilePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return err
		}
		_, err = f.WriteString(block)
		_ = f.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

func removeWindowsCompletionHooks(o Options, res *Result) {
	home := os.Getenv("USERPROFILE")
	if home == "" {
		home, _ = os.UserHomeDir()
	}
	profiles := []string{
		filepath.Join(home, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"),
		filepath.Join(home, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"),
	}
	for _, profilePath := range profiles {
		res.Plan = append(res.Plan, "strip completion hook "+profilePath)
		if o.DryRun {
			continue
		}
		b, err := os.ReadFile(profilePath)
		if err != nil {
			continue
		}
		lines := strings.Split(string(b), "\n")
		var keep []string
		skipNext := false
		for _, line := range lines {
			if skipNext {
				skipNext = false
				continue
			}
			if strings.Contains(line, "Millennium Helpers completions") {
				skipNext = true
				continue
			}
			if strings.Contains(line, "millennium-helpers.completion.ps1") {
				continue
			}
			keep = append(keep, line)
		}
		_ = os.WriteFile(profilePath, []byte(strings.Join(keep, "\n")), 0o644)
	}
}
