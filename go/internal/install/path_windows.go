//go:build windows

package install

import (
	"fmt"
	"os"

	"golang.org/x/sys/windows/registry"
)

func installWindowsPATH(o Options, res *Result) error {
	if os.Getenv("PSTESTS") == "true" {
		res.Plan = append(res.Plan, "[TEST] skip User PATH update for "+o.TargetDir)
		return nil
	}
	res.Plan = append(res.Plan, "add User PATH "+o.TargetDir)
	if o.DryRun {
		return nil
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, `Environment`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("open User Environment: %w", err)
	}
	defer k.Close()
	cur, _, err := k.GetStringValue("Path")
	if err != nil && err != registry.ErrNotExist {
		return err
	}
	newPath, added := pathWithDir(cur, o.TargetDir)
	if !added {
		res.Plan = append(res.Plan, "User PATH already contains "+o.TargetDir)
		return nil
	}
	return k.SetStringValue("Path", newPath)
}

func removeWindowsPATH(o Options, res *Result) {
	if os.Getenv("PSTESTS") == "true" {
		res.Plan = append(res.Plan, "[TEST] skip User PATH remove for "+o.TargetDir)
		return
	}
	res.Plan = append(res.Plan, "remove User PATH "+o.TargetDir)
	if o.DryRun {
		return
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, `Environment`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return
	}
	defer k.Close()
	cur, _, err := k.GetStringValue("Path")
	if err != nil {
		return
	}
	_ = k.SetStringValue("Path", pathWithoutDir(cur, o.TargetDir))
}
