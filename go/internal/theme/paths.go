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
	candidate := filepath.Join(skins, component)
	resolved, err := filepath.Abs(candidate)
	if err != nil {
		return "", err
	}
	skinsAbs, err := filepath.Abs(skins)
	if err != nil {
		return "", err
	}
	// Prefer EvalSymlinks when paths exist; fall back to abs for not-yet-created theme dirs.
	if r, e := filepath.EvalSymlinks(skinsAbs); e == nil {
		skinsAbs = r
	}
	if _, e := os.Stat(resolved); e == nil {
		if r, e2 := filepath.EvalSymlinks(resolved); e2 == nil {
			resolved = r
		}
	}
	sep := string(os.PathSeparator)
	if resolved != skinsAbs && !strings.HasPrefix(resolved, skinsAbs+sep) {
		return "", fmt.Errorf("Error: Resolved theme path '%s' escapes the skins directory.", resolved)
	}
	return resolved, nil
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
