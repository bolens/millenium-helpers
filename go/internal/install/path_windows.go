//go:build windows

package install

import (
	"fmt"
	"os"
	"strings"

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
	parts := splitPath(cur)
	for _, p := range parts {
		if strings.EqualFold(p, o.TargetDir) {
			res.Plan = append(res.Plan, "User PATH already contains "+o.TargetDir)
			return nil
		}
	}
	newPath := o.TargetDir
	if cur != "" {
		if strings.HasSuffix(cur, ";") {
			newPath = cur + o.TargetDir
		} else {
			newPath = cur + ";" + o.TargetDir
		}
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
	var keep []string
	for _, p := range splitPath(cur) {
		if p == "" || strings.EqualFold(p, o.TargetDir) {
			continue
		}
		keep = append(keep, p)
	}
	_ = k.SetStringValue("Path", strings.Join(keep, ";"))
}

func splitPath(p string) []string {
	if p == "" {
		return nil
	}
	return strings.Split(p, ";")
}
