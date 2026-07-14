//go:build windows

package steam

func fileOwner(path string) (string, error) {
	_ = path
	return "", nil
}

func chownUser(path, username string) {
	_, _ = path, username
}

func effectiveUID() int { return -1 }
