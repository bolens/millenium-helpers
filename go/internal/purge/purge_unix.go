//go:build unix

package purge

func planWindows() []Action { return nil }

func applyWindowsExtra(a Action) error { return nil }

func ensureSteamClosedForPurge(yes bool) (relaunch bool, err error) {
	_ = yes
	return false, nil
}

func relaunchSteamBestEffort() {}
