package install

import (
	"os/exec"
	"strings"
)

func runGitRevParse(dir string) (string, error) {
	cmd := exec.Command("git", "-C", dir, "rev-parse", "--short", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
