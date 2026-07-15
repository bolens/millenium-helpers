package install

import (
	"fmt"
	"runtime"
	"strings"
)

// HelpersGitHubRepo is the GitHub owner/repo for helpers releases.
const HelpersGitHubRepo = "bolens/millenium-helpers"

// NormalizeTag returns vX.Y.Z form.
func NormalizeTag(tag string) (string, error) {
	tag = strings.TrimSpace(tag)
	tag = strings.TrimPrefix(tag, "v")
	if tag == "" {
		return "", fmt.Errorf("empty tag")
	}
	return "v" + tag, nil
}

// AssetHelpers names the versioned helpers archive (tar.gz/zip).
func AssetHelpers(version, osName, arch, ext string) string {
	version = strings.TrimPrefix(version, "v")
	return fmt.Sprintf("millennium-helpers-v%s-%s-%s.%s", version, osName, arch, ext)
}

// AssetSrc names the versioned source archive.
func AssetSrc(version, ext string) string {
	version = strings.TrimPrefix(version, "v")
	return fmt.Sprintf("millennium-helpers-v%s-src.%s", version, ext)
}

// AssetGo names the standalone Go binary release asset.
func AssetGo(version, osName, arch string) string {
	version = strings.TrimPrefix(version, "v")
	suffix := ""
	if osName == "windows" {
		suffix = ".exe"
	}
	return fmt.Sprintf("millennium-v%s-%s-%s%s", version, osName, arch, suffix)
}

// HostArch maps runtime arch to release labels amd64|arm64.
func HostArch() (string, error) {
	switch runtime.GOARCH {
	case "amd64":
		return "amd64", nil
	case "arm64":
		return "arm64", nil
	default:
		return "", fmt.Errorf("unsupported arch %q (expected amd64 or arm64)", runtime.GOARCH)
	}
}

// HostUnixOS maps GOOS to linux|darwin for Unix helpers packs.
func HostUnixOS() (string, error) {
	switch runtime.GOOS {
	case "linux":
		return "linux", nil
	case "darwin":
		return "darwin", nil
	default:
		return "", fmt.Errorf("unsupported unix OS %q", runtime.GOOS)
	}
}

// TwinNames are PATH long-name argv0 twins installed beside millennium.
func TwinNames() []string {
	return []string{
		"millennium-repair",
		"millennium-upgrade",
		"millennium-schedule",
		"millennium-purge",
		"millennium-diag",
		"millennium-theme",
		"millennium-mcp",
	}
}
