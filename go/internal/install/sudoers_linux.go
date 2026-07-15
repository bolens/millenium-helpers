//go:build linux

package install

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
)

func sudoersPath() string {
	if v := os.Getenv("MOCK_SUDOERS_FILE"); v != "" {
		return v
	}
	return "/etc/sudoers.d/millennium-helpers"
}

func installSudoers(o Options, res *Result) error {
	if os.Geteuid() != 0 && os.Getenv("MOCK_SUDOERS_FILE") == "" {
		res.Plan = append(res.Plan, "skip sudoers (not root)")
		return nil
	}
	userName := os.Getenv("SUDO_USER")
	if userName == "" || userName == "root" {
		if u, err := user.Current(); err == nil && u.Username != "root" {
			userName = u.Username
		}
	}
	if userName == "" || userName == "root" {
		res.Plan = append(res.Plan, "skip sudoers (no non-root install user)")
		return nil
	}
	path := sudoersPath()
	line := SudoersLine(userName, o.TargetDir)
	res.Plan = append(res.Plan, "write sudoers "+path)
	if o.DryRun {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(line), 0o440); err != nil {
		return err
	}
	if _, err := exec.LookPath("visudo"); err == nil {
		cmd := exec.Command("visudo", "-cf", tmp)
		if out, err := cmd.CombinedOutput(); err != nil {
			_ = os.Remove(tmp)
			return fmt.Errorf("visudo validation failed: %s: %w", string(out), err)
		}
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	_ = os.Chown(path, 0, 0)
	_ = os.Chmod(path, 0o440)
	return nil
}

func removeSudoers(o Options, res *Result) {
	_ = planRemove(sudoersPath(), o.DryRun, &res.Plan)
}
