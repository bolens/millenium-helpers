package theme

import "github.com/bolens/millenium-helpers/internal/archive"

// SafeExtractZip extracts zipPath into destDir, rejecting zip-slip members.
func SafeExtractZip(zipPath, destDir string) error {
	return archive.SafeExtractZip(zipPath, destDir)
}
