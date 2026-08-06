//go:build unix

package atomicfile

import "os"

func replaceFile(source, target string) error {
	return os.Rename(source, target)
}
