//go:build !windows

package install

import (
	"os"
	"path/filepath"
	"runtime"
)

func installUnixCompletionsAndMan(o Options, sourceRoot string, res *Result) error {
	compRoot := filepath.Join(sourceRoot, "completions")
	bashSrc := filepath.Join(compRoot, "bash", "millennium-helpers")
	zshSrc := filepath.Join(compRoot, "zsh", "_millennium-helpers")
	fishSrc := filepath.Join(compRoot, "fish", "millennium.fish")
	nuSrc := filepath.Join(compRoot, "nushell", "millennium-helpers.nu")

	bashDir := envOr("MILLENNIUM_BASH_COMPLETION_DIR", defaultBashCompDir())
	zshDir := envOr("MILLENNIUM_ZSH_COMPLETION_DIR", defaultZshCompDir())
	fishDir := envOr("MILLENNIUM_FISH_COMPLETION_DIR", defaultFishCompDir())
	nuDir := envOr("MILLENNIUM_NUSHELL_COMPLETION_DIR", defaultNuCompDir())
	manDir := envOr("MILLENNIUM_MAN_DIR", defaultManDir())

	if _, err := os.Stat(bashSrc); err == nil {
		if err := ensureDir(bashDir, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if err := planCopy(bashSrc, filepath.Join(bashDir, "millennium-helpers"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	if _, err := os.Stat(zshSrc); err == nil {
		if err := ensureDir(zshDir, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if err := planCopy(zshSrc, filepath.Join(zshDir, "_millennium-helpers"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	if _, err := os.Stat(fishSrc); err == nil {
		if err := ensureDir(fishDir, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if err := planCopy(fishSrc, filepath.Join(fishDir, "millennium.fish"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	if _, err := os.Stat(nuSrc); err == nil {
		if err := ensureDir(nuDir, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if err := planCopy(nuSrc, filepath.Join(nuDir, "millennium-helpers.nu"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}

	manSrc := filepath.Join(sourceRoot, "man")
	if st, err := os.Stat(manSrc); err == nil && st.IsDir() {
		if err := ensureDir(manDir, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if o.DryRun {
			res.Plan = append(res.Plan, "install man/*.1 → "+manDir)
		} else {
			if err := copyTreeFiles(manSrc, manDir, "*.1"); err != nil {
				return err
			}
		}
	}
	return nil
}

func removeUnixCompletionsAndMan(o Options, res *Result) {
	bashDir := envOr("MILLENNIUM_BASH_COMPLETION_DIR", defaultBashCompDir())
	zshDir := envOr("MILLENNIUM_ZSH_COMPLETION_DIR", defaultZshCompDir())
	fishDir := envOr("MILLENNIUM_FISH_COMPLETION_DIR", defaultFishCompDir())
	nuDir := envOr("MILLENNIUM_NUSHELL_COMPLETION_DIR", defaultNuCompDir())
	manDir := envOr("MILLENNIUM_MAN_DIR", defaultManDir())
	_ = planRemove(filepath.Join(bashDir, "millennium-helpers"), o.DryRun, &res.Plan)
	_ = planRemove(filepath.Join(zshDir, "_millennium-helpers"), o.DryRun, &res.Plan)
	_ = planRemove(filepath.Join(fishDir, "millennium.fish"), o.DryRun, &res.Plan)
	_ = planRemove(filepath.Join(fishDir, "millennium-helpers.fish"), o.DryRun, &res.Plan) // legacy name
	_ = planRemove(filepath.Join(nuDir, "millennium-helpers.nu"), o.DryRun, &res.Plan)
	for _, page := range []string{
		"millennium.1", "millennium-diag.1", "millennium-mcp.1", "millennium-purge.1",
		"millennium-repair.1", "millennium-schedule.1", "millennium-theme.1", "millennium-upgrade.1",
		"millennium-install.1", "millennium-uninstall.1",
	} {
		_ = planRemove(filepath.Join(manDir, page), o.DryRun, &res.Plan)
	}
}

func defaultBashCompDir() string {
	if runtime.GOOS == "darwin" {
		return "/opt/homebrew/etc/bash_completion.d"
	}
	return "/usr/share/bash-completion/completions"
}

func defaultZshCompDir() string {
	if runtime.GOOS == "darwin" {
		return "/opt/homebrew/share/zsh/site-functions"
	}
	return "/usr/local/share/zsh/site-functions"
}

func defaultFishCompDir() string {
	if runtime.GOOS == "darwin" {
		return "/opt/homebrew/share/fish/vendor_completions.d"
	}
	return "/usr/share/fish/vendor_completions.d"
}

func defaultNuCompDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "nushell", "completions")
}

func defaultManDir() string {
	if runtime.GOOS == "darwin" {
		return "/opt/homebrew/share/man/man1"
	}
	return "/usr/local/share/man/man1"
}

func installWindowsExtras(Options, string, *Result) error { return nil }
