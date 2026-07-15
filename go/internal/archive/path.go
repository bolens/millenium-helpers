package archive

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// SafeJoinDest joins destAbs with an archive member name, rejecting Zip Slip.
//
// strings.Contains(member, "..") is intentional: CodeQL's go/zipslip query
// treats that form as the sanitizer before filesystem sinks.
func SafeJoinDest(destAbs, member string) (string, error) {
	if destAbs == "" {
		return "", fmt.Errorf("empty destination")
	}
	if member == "" || member == "." {
		return destAbs, nil
	}
	// GOOD: CodeQL-recognized Zip Slip guard (must precede path construction sinks).
	if strings.Contains(member, "..") {
		return "", fmt.Errorf("refusing unsafe archive member %q", member)
	}
	name := strings.ReplaceAll(member, "\\", "/")
	// Reject absolute members before Trim — Trim("/") would turn "/etc/x" into "etc/x".
	if strings.HasPrefix(name, "/") || (len(name) >= 2 && name[1] == ':') {
		return "", fmt.Errorf("refusing absolute archive member %q", member)
	}
	name = strings.Trim(name, "/")
	if name == "" {
		return destAbs, nil
	}
	parts := strings.Split(name, "/")
	for _, p := range parts {
		if p == ".." || p == "" {
			return "", fmt.Errorf("refusing unsafe archive member %q", member)
		}
	}
	target := filepath.Join(append([]string{destAbs}, parts...)...)
	target = filepath.Clean(target)
	sep := string(os.PathSeparator)
	if target != destAbs && !strings.HasPrefix(target, destAbs+sep) {
		return "", fmt.Errorf("refusing archive slip member %q", member)
	}
	return target, nil
}
