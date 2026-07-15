package install

import "path/filepath"

// SudoersLine builds the NOPASSWD line for privileged millennium verbs.
func SudoersLine(userName, targetDir string) string {
	m := filepath.Join(targetDir, "millennium")
	return userName + " ALL=(ALL) NOPASSWD: " +
		m + " upgrade, " + m + " upgrade *, " +
		m + " diag, " + m + " diag *, " +
		m + " repair, " + m + " repair *, " +
		m + " purge, " + m + " purge *\n"
}
