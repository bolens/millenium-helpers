//go:build linux

package upgrade

import (
	"bufio"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
)

var passwdPath = "/etc/passwd"

func hookHomes(allUsers bool) ([]string, error) {
	if !allUsers {
		if os.Geteuid() == 0 {
			if sudoUser := strings.TrimSpace(os.Getenv("SUDO_USER")); sudoUser != "" && sudoUser != "root" {
				u, err := user.Lookup(sudoUser)
				if err != nil {
					return nil, fmt.Errorf("resolve SUDO_USER %q: %w", sudoUser, err)
				}
				return []string{u.HomeDir}, nil
			}
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		return []string{home}, nil
	}
	return passwdHomes(passwdPath)
}

func passwdHomes(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()

	var homes []string
	seen := map[string]bool{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), ":")
		if len(fields) < 7 {
			continue
		}
		uid, err := strconv.Atoi(fields[2])
		home := filepath.Clean(fields[5])
		shell := fields[6]
		if err != nil || uid < 1000 || uid == 65534 || !filepath.IsAbs(home) ||
			home == "/" || strings.HasSuffix(shell, "/nologin") || strings.HasSuffix(shell, "/false") ||
			seen[home] {
			continue
		}
		seen[home] = true
		homes = append(homes, home)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return homes, nil
}
