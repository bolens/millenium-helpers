//go:build windows

package injection

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/bolens/millenium-helpers/internal/theme"
)

const disabledSuffix = ".millennium-disabled"

func windowsPaths() (string, string, error) {
	steam := theme.FindSteamDir()
	if steam == "" {
		return "", "", fmt.Errorf("Steam directory not found")
	}
	if info, err := os.Stat(filepath.Join(steam, "millennium")); err != nil || !info.IsDir() {
		return "", "", fmt.Errorf("Millennium client directory not found under Steam")
	}
	hook := filepath.Join(steam, "wsock32.dll")
	return hook, hook + disabledSuffix, nil
}

func platformStatus() (string, []string, error) {
	hook, disabled, err := windowsPaths()
	if err != nil {
		return "unavailable", nil, err
	}
	_, hookErr := os.Stat(hook)
	_, disabledErr := os.Stat(disabled)
	if hookErr == nil && disabledErr == nil {
		return "partial", []string{"active and disabled bootstrap DLLs both exist: " + hook}, nil
	}
	if hookErr == nil {
		return "enabled", []string{"enabled: " + hook}, nil
	}
	if disabledErr == nil {
		return "disabled", []string{"disabled: " + hook}, nil
	}
	return "unavailable", []string{"missing: " + hook}, nil
}

func platformSetEnabled(enable, dryRun bool) ([]string, error) {
	hook, disabled, err := windowsPaths()
	if err != nil {
		return nil, err
	}
	if enable {
		if _, err := os.Stat(hook); err == nil {
			if _, disabledErr := os.Stat(disabled); disabledErr == nil {
				return nil, fmt.Errorf("refusing to overwrite while both %s and %s exist", hook, disabled)
			}
			return []string{"Injection is already enabled."}, nil
		}
		if _, err := os.Stat(disabled); err != nil {
			return nil, fmt.Errorf("disabled bootstrap DLL not found at %s (run upgrade first)", disabled)
		}
		if !dryRun {
			if err := os.Rename(disabled, hook); err != nil {
				return nil, err
			}
		}
		return []string{"Enable: " + hook}, nil
	}
	if _, err := os.Stat(disabled); err == nil {
		if _, hookErr := os.Stat(hook); hookErr == nil {
			return nil, fmt.Errorf("refusing to overwrite while both %s and %s exist", hook, disabled)
		}
		return []string{"Injection is already disabled."}, nil
	}
	if _, err := os.Stat(hook); err != nil {
		return []string{"Injection is already disabled."}, nil
	}
	if !dryRun {
		if err := os.Rename(hook, disabled); err != nil {
			return nil, err
		}
	}
	return []string{"Disable: " + hook}, nil
}
