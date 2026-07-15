//go:build !linux

package install

func installSudoers(o Options, res *Result) error {
	res.Plan = append(res.Plan, "skip sudoers (non-Linux)")
	return nil
}

func removeSudoers(o Options, res *Result) {}

// SudoersLine is exported for tests on all platforms.
func SudoersLine(userName, targetDir string) string {
	return userName + " ALL=(ALL) NOPASSWD: " + targetDir + "/millennium upgrade\n"
}
