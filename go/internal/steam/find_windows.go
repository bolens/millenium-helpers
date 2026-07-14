//go:build windows

package steam

import (
	"os"
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

func dirCandidates() []string {
	out := dirCandidatesCommon()
	out = append(out, windowsRegistrySteamPaths()...)
	if pf := os.Getenv("ProgramFiles(x86)"); pf != "" {
		out = append(out, filepath.Join(pf, "Steam"))
	}
	if pf := os.Getenv("ProgramFiles"); pf != "" {
		out = append(out, filepath.Join(pf, "Steam"))
	}
	out = append(out, `C:\Steam`)
	return out
}

func windowsRegistrySteamPaths() []string {
	var paths []string
	try := func(k registry.Key, path, value string) {
		key, err := registry.OpenKey(k, path, registry.QUERY_VALUE)
		if err != nil {
			return
		}
		defer key.Close()
		v, _, err := key.GetStringValue(value)
		if err == nil && v != "" {
			paths = append(paths, v)
		}
	}
	try(registry.CURRENT_USER, `Software\Valve\Steam`, "SteamPath")
	try(registry.LOCAL_MACHINE, `SOFTWARE\WOW6432Node\Valve\Steam`, "InstallPath")
	try(registry.LOCAL_MACHINE, `SOFTWARE\Valve\Steam`, "InstallPath")
	return paths
}
