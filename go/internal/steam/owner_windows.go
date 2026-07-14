//go:build windows

package steam

func fileOwner(path string) (string, error) {
	_ = path
	return "", nil
}

func chownUser(path, username string) {
	_, _ = path, username
}

// ChownUser is a no-op on Windows.
func ChownUser(path, username string) { chownUser(path, username) }

func effectiveUID() int { return -1 }
