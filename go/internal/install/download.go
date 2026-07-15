package install

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/githubapi"
	"github.com/bolens/millenium-helpers/internal/upgrade"
)

// FetchHelpersTree downloads/verifies/extracts a helpers archive for the track.
// Caller must remove the returned tempDir when done.
func FetchHelpersTree(o Options) (sourceRoot, tempDir string, resolved ResolvedTrack, err error) {
	platform := "linux"
	if runtime.GOOS == "windows" {
		platform = "windows"
	}
	resolved, err = ResolveTrackURLs(o.Track, o.Tag, platform)
	if err != nil {
		return "", "", resolved, err
	}
	if resolved.Track == "main" && !o.AllowUnsignedMain {
		return "", "", resolved, fmt.Errorf("track main requires --allow-unsigned-main (unsigned tip-of-main archive)")
	}
	if resolved.URL == "" {
		return "", "", resolved, fmt.Errorf("track %q has no download URL", resolved.Track)
	}

	tempDir, err = os.MkdirTemp("", "millennium-helpers-install-*")
	if err != nil {
		return "", "", resolved, err
	}
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.RemoveAll(tempDir)
		}
	}()

	ext := ".tar.gz"
	if strings.HasSuffix(strings.ToLower(resolved.URL), ".zip") {
		ext = ".zip"
	}
	archivePath := filepath.Join(tempDir, "helpers"+ext)
	if err := githubapi.Download(resolved.URL, archivePath); err != nil {
		return "", "", resolved, fmt.Errorf("download helpers archive: %w", err)
	}
	if resolved.NeedsSHA {
		sha, err := githubapi.FetchFirstFieldSHA(resolved.SHAURL)
		if err != nil {
			return "", "", resolved, fmt.Errorf("fetch checksum: %w", err)
		}
		if err := upgrade.VerifyFileSHA256(archivePath, sha); err != nil {
			return "", "", resolved, err
		}
	}
	extractDir := filepath.Join(tempDir, "extract")
	if err := os.MkdirAll(extractDir, 0o755); err != nil {
		return "", "", resolved, err
	}
	if err := extractHelpersArchive(archivePath, extractDir); err != nil {
		return "", "", resolved, fmt.Errorf("extract helpers archive: %w", err)
	}
	sourceRoot, err = findExtractedSourceRoot(extractDir)
	if err != nil {
		return "", "", resolved, err
	}
	cleanup = false
	return sourceRoot, tempDir, resolved, nil
}
