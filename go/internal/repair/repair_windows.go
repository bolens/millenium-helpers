//go:build windows

package repair

func chownTree(path string) error {
	_ = path
	return nil
}
