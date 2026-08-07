//go:build unix

package injection

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/bolens/millenium-helpers/internal/repair"
)

const disabledSuffix = ".millennium-disabled"

func platformStatus() (string, []string, error) {
	if runtime.GOOS == "darwin" {
		return "unsupported", []string{"This helpers installation does not install a Millennium bootstrap hook on macOS."}, nil
	}
	plans := repair.PlanHooks()
	if len(plans) == 0 {
		return "unavailable", nil, fmt.Errorf("no Steam directories found")
	}
	enabled, disabled := 0, 0
	var details []string
	for _, plan := range plans {
		switch {
		case validHook(plan.Hook, plan.Target):
			enabled++
			details = append(details, "enabled: "+plan.Hook)
		case validHook(plan.Hook+disabledSuffix, plan.Target):
			disabled++
			details = append(details, "disabled: "+plan.Hook)
		default:
			details = append(details, "missing: "+plan.Hook)
		}
	}
	state := "partial"
	if enabled == len(plans) {
		state = "enabled"
	} else if disabled == len(plans) {
		state = "disabled"
	}
	return state, details, nil
}

func platformSetEnabled(enable, dryRun bool) ([]string, error) {
	if runtime.GOOS == "darwin" {
		return nil, fmt.Errorf("Millennium bootstrap injection is not installed by these helpers on macOS")
	}
	plans := repair.PlanHooks()
	if len(plans) == 0 {
		return nil, fmt.Errorf("no Steam directories found")
	}
	// Validate every destination before mutating any hook so a foreign file
	// cannot leave a multi-architecture install only partially changed.
	for _, plan := range plans {
		disabled := plan.Hook + disabledSuffix
		if _, err := os.Lstat(plan.Hook); err == nil && !validHook(plan.Hook, plan.Target) {
			return nil, fmt.Errorf("refusing to modify non-Millennium hook %s", plan.Hook)
		}
		if _, err := os.Lstat(disabled); err == nil && !validHook(disabled, plan.Target) {
			return nil, fmt.Errorf("refusing to overwrite non-Millennium file %s", disabled)
		}
	}
	var details []string
	for _, plan := range plans {
		disabled := plan.Hook + disabledSuffix
		if enable {
			if validHook(plan.Hook, plan.Target) {
				continue
			}
			if !validHook(disabled, plan.Target) {
				if _, err := os.Stat(plan.Target); err != nil {
					return nil, fmt.Errorf("bootstrap library missing at %s (run upgrade first)", plan.Target)
				}
				details = append(details, "Enable: "+plan.Hook+" -> "+plan.Target)
				if !dryRun {
					if err := os.MkdirAll(filepath.Dir(plan.Hook), 0o755); err != nil {
						return nil, err
					}
					if err := os.Symlink(plan.Target, plan.Hook); err != nil {
						return nil, err
					}
				}
				continue
			}
			details = append(details, "Enable: "+plan.Hook)
			if !dryRun {
				if err := os.Rename(disabled, plan.Hook); err != nil {
					return nil, err
				}
			}
			continue
		}
		if validHook(disabled, plan.Target) {
			continue
		}
		if !validHook(plan.Hook, plan.Target) {
			continue
		}
		details = append(details, "Disable: "+plan.Hook)
		if !dryRun {
			if err := os.Rename(plan.Hook, disabled); err != nil {
				return nil, err
			}
		}
	}
	if len(details) == 0 {
		if enable {
			details = append(details, "Injection is already enabled.")
		} else {
			details = append(details, "Injection is already disabled.")
		}
	}
	return details, nil
}

func validHook(path, target string) bool {
	got, err := os.Readlink(path)
	if err != nil {
		return false
	}
	if !filepath.IsAbs(got) {
		got = filepath.Join(filepath.Dir(path), got)
	}
	return filepath.Clean(got) == filepath.Clean(target)
}
