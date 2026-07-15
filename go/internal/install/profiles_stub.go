//go:build !windows

package install

func installWindowsCompletionHooks(Options, *Result) error { return nil }
func removeWindowsCompletionHooks(Options, *Result)       {}
