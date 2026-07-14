//go:build unix

package repair

import (
	"os"
	"path/filepath"
)

func chownTree(path string) error {
	uid := os.Getuid()
	gid := os.Getgid()
	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		return os.Chown(p, uid, gid)
	})
}
