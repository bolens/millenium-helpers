package install

import "strings"

// splitPath splits a Windows-style PATH (semicolon-separated).
func splitPath(p string) []string {
	if p == "" {
		return nil
	}
	return strings.Split(p, ";")
}

// pathWithDir prepends dir to a Windows User PATH value if missing.
// added is false when dir was already present (case-insensitive).
func pathWithDir(cur, dir string) (newPath string, added bool) {
	for _, p := range splitPath(cur) {
		if strings.EqualFold(p, dir) {
			return cur, false
		}
	}
	if cur == "" {
		return dir, true
	}
	if strings.HasSuffix(cur, ";") {
		return cur + dir, true
	}
	return cur + ";" + dir, true
}

// pathWithoutDir removes dir entries from a Windows User PATH value.
func pathWithoutDir(cur, dir string) string {
	var keep []string
	for _, p := range splitPath(cur) {
		if p == "" || strings.EqualFold(p, dir) {
			continue
		}
		keep = append(keep, p)
	}
	return strings.Join(keep, ";")
}
