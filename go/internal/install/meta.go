package install

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// MetaFileName is written next to the install lib root (Unix) or install root (Windows).
const MetaFileName = "install-meta.json"

// Meta is install-meta.json.
type Meta struct {
	Track         string `json:"track"`
	Ref           string `json:"ref,omitempty"`
	Version       string `json:"version,omitempty"`
	SourceURL     string `json:"source_url,omitempty"`
	InstalledAt   string `json:"installed_at"`
	MigratedFrom  string `json:"migrated_from,omitempty"`
}

// MetaPath returns the meta path under an install meta root (lib dir or Windows install root).
func MetaPath(metaRoot string) string {
	return filepath.Join(metaRoot, MetaFileName)
}

// WriteMeta writes install-meta.json.
func WriteMeta(metaRoot string, m Meta) error {
	if err := os.MkdirAll(metaRoot, 0o755); err != nil {
		return err
	}
	if m.InstalledAt == "" {
		m.InstalledAt = time.Now().UTC().Format(time.RFC3339)
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return os.WriteFile(MetaPath(metaRoot), b, 0o644)
}

// ReadMeta loads install-meta.json or returns nil,false.
func ReadMeta(metaRoot string) (*Meta, bool, error) {
	p := MetaPath(metaRoot)
	b, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, false, nil
		}
		return nil, false, err
	}
	var m Meta
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, false, err
	}
	return &m, true, nil
}

// MigrateMetaIfNeeded writes meta for legacy installs without one.
func MigrateMetaIfNeeded(metaRoot, method, checkout string) error {
	if _, ok, err := ReadMeta(metaRoot); err != nil {
		return err
	} else if ok {
		return nil
	}
	version := ""
	if b, err := os.ReadFile(filepath.Join(metaRoot, "VERSION")); err == nil {
		version = strings.TrimSpace(string(b))
	}
	track := "release"
	ref := "latest"
	switch method {
	case "pacman-git", "scoop-git", "winget-git", "main":
		track = "main"
		ref = "main"
	case "checkout":
		track = "checkout"
		ref = "checkout"
		if checkout != "" {
			if out, err := gitShortHEAD(checkout); err == nil && out != "" {
				ref = out
			}
		}
	default:
		if version != "" {
			ref = "v" + strings.TrimPrefix(version, "v")
		}
	}
	return WriteMeta(metaRoot, Meta{
		Track:        track,
		Ref:          ref,
		Version:      version,
		MigratedFrom: "legacy",
	})
}

func gitShortHEAD(dir string) (string, error) {
	// Avoid importing os/exec in every path — use a tiny helper.
	return runGitRevParse(dir)
}

// InferCheckoutTrack returns checkout when sourceRoot has .git.
func InferCheckoutTrack(sourceRoot string) bool {
	if sourceRoot == "" {
		return false
	}
	st, err := os.Stat(filepath.Join(sourceRoot, ".git"))
	return err == nil && (st.IsDir() || st.Mode().IsRegular())
}

// ValidateTrack normalizes track/tag.
func ValidateTrack(track, tag string) (string, string, error) {
	track = strings.ToLower(strings.TrimSpace(track))
	if tag != "" {
		track = "tag"
	}
	if track == "" {
		track = "release"
	}
	switch track {
	case "release", "main", "tag", "checkout":
	default:
		return "", "", fmt.Errorf("invalid helpers track %q (expected release|main|tag|checkout)", track)
	}
	if track == "tag" {
		norm, err := NormalizeTag(tag)
		if err != nil {
			return "", "", fmt.Errorf("--tag required for track=tag: %w", err)
		}
		tag = norm
	}
	return track, tag, nil
}
