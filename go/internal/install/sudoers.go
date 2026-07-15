package install

import (
	"path"
	"path/filepath"
)

// SudoersLine builds the NOPASSWD line for privileged millennium verbs.
// Paths use forward slashes (sudoers is Linux-only even when unit-tested on Windows).
func SudoersLine(userName, targetDir string) string {
	m := path.Join(filepath.ToSlash(targetDir), "millennium")
	return userName + " ALL=(ALL) NOPASSWD: " +
		m + " upgrade, " + m + " upgrade *, " +
		m + " diag, " + m + " diag *, " +
		m + " repair, " + m + " repair *, " +
		m + " purge, " + m + " purge *\n"
}
