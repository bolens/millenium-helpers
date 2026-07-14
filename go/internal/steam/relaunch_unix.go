//go:build unix

package steam

import (
	"os"
	"os/exec"
	"path/filepath"
)

// RelaunchBestEffort starts Steam from FindDir or PATH.
func RelaunchBestEffort() {
	steam := FindDir()
	if steam != "" {
		for _, name := range []string{"steam", "steam.sh"} {
			p := filepath.Join(steam, name)
			if st, err := os.Stat(p); err == nil && !st.IsDir() {
				_ = exec.Command(p).Start()
				return
			}
		}
	}
	_ = exec.Command("steam").Start()
}
