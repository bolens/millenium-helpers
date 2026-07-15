//go:build !windows

package install

func installWindowsPATH(Options, *Result) error { return nil }
func removeWindowsPATH(Options, *Result)       {}
