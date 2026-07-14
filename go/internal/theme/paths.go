package theme

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// SanitizeComponent rejects empty, ., .., and path separators.
func SanitizeComponent(value, label string) error {
	if value == "" || value == "." || value == ".." || strings.ContainsAny(value, `/\`) {
		return fmt.Errorf("Error: Invalid %s '%s'.", label, value)
	}
	return nil
}

// ResolveThemeDir joins skins/component and ensures it stays under skins.
func ResolveThemeDir(skins, component string) (string, error) {
	if err := SanitizeComponent(component, "theme name"); err != nil {
		return "", err
	}
	skinsAbs, err := filepath.Abs(skins)
	if err != nil {
		return "", err
	}
	if r, e := filepath.EvalSymlinks(skinsAbs); e == nil {
		skinsAbs = r
	}
	// Single sanitized segment cannot escape skinsAbs when the target does not exist yet
	// (avoids macOS /var vs /private/var and Windows 8.3 short-name mismatches).
	candidate := filepath.Join(skinsAbs, component)
	if _, err := os.Lstat(candidate); err != nil {
		if os.IsNotExist(err) {
			return candidate, nil
		}
		return "", err
	}

	resolved := candidate
	if r, e := filepath.EvalSymlinks(candidate); e == nil {
		resolved = r
	}
	if !pathContained(skinsAbs, resolved) {
		// Windows short vs long paths: SameFile on the parent of the theme dir.
		if samePath(skinsAbs, filepath.Dir(resolved)) && filepath.Base(resolved) == component {
			return resolved, nil
		}
		return "", fmt.Errorf("Error: Resolved theme path '%s' escapes the skins directory.", resolved)
	}
	return resolved, nil
}

func pathContained(base, target string) bool {
	rel, err := filepath.Rel(base, target)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))
}

func samePath(a, b string) bool {
	fa, err1 := os.Stat(a)
	fb, err2 := os.Stat(b)
	if err1 != nil || err2 != nil {
		return false
	}
	return os.SameFile(fa, fb)
}

// ParseOwnerRepo splits owner/repo (Windows backslashes normalized to /).
func ParseOwnerRepo(arg string) (owner, repo string, err error) {
	arg = strings.ReplaceAll(arg, `\`, "/")
	parts := strings.Split(arg, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("Error: Theme must be in 'owner/repo' format.")
	}
	if err := SanitizeComponent(parts[0], "theme owner"); err != nil {
		return "", "", err
	}
	if err := SanitizeComponent(parts[1], "theme repo"); err != nil {
		return "", "", err
	}
	return parts[0], parts[1], nil
}
