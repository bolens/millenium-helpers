package install

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/archive"
)

func extractHelpersArchive(archivePath, destDir string) error {
	lower := strings.ToLower(archivePath)
	switch {
	case strings.HasSuffix(lower, ".zip"):
		return archive.SafeExtractZip(archivePath, destDir)
	case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
		return archive.SafeExtractTarGz(archivePath, destDir)
	default:
		return fmt.Errorf("unsupported helpers archive type: %s", filepath.Base(archivePath))
	}
}

// findExtractedSourceRoot locates VERSION (+ go or bin) under extractDir.
func findExtractedSourceRoot(extractDir string) (string, error) {
	if looksLikeSourceRoot(extractDir) {
		return extractDir, nil
	}
	entries, err := os.ReadDir(extractDir)
	if err != nil {
		return "", err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		cand := filepath.Join(extractDir, e.Name())
		if looksLikeSourceRoot(cand) {
			return cand, nil
		}
	}
	return "", fmt.Errorf("extracted archive has no helpers source root under %s", extractDir)
}
