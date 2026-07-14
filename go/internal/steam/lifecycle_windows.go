//go:build windows

package steam

import "fmt"

// Windows scheduled tasks do not use Unix pre/post Steam hooks.

func IsSteamRunning() bool { return false }

func IsGameRunning() bool { return false }

func CaptureEnv(username, home string) error {
	_, _ = username, home
	return fmt.Errorf("Steam env capture is not supported on Windows")
}

func CloseGracefully(username, home string) error {
	_, _ = username, home
	return fmt.Errorf("Steam close is not supported via schedule hooks on Windows")
}

func RelaunchFromState(username, home string) (bool, error) {
	_, _ = username, home
	return false, nil
}
