package theme

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/githubapi"
)

// Test seams
var (
	latestCommit = githubapi.LatestCommit
	downloadURL  = githubapi.Download
)

// themeLatestCommit honors MILLENNIUM_THEME_MOCK_COMMIT for offline behavioral
// tests ("fail" forces an error); otherwise uses the latestCommit seam.
func themeLatestCommit(owner, repo string) (string, error) {
	if mock := strings.TrimSpace(os.Getenv("MILLENNIUM_THEME_MOCK_COMMIT")); mock != "" {
		if mock == "fail" {
			return "", fmt.Errorf("mock GitHub API failure")
		}
		return mock, nil
	}
	return latestCommit(owner, repo)
}

type metadata struct {
	Commit string `json:"commit"`
	Owner  string `json:"owner"`
	Repo   string `json:"repo"`
}

func injectTokenFromConfig() {
	if os.Getenv("GITHUB_TOKEN") != "" {
		return
	}
	data, err := config.Load()
	if err != nil {
		return
	}
	if tok := config.Get(data, "github_token"); tok != "" {
		_ = os.Setenv("GITHUB_TOKEN", tok)
	}
}

func writeMetadata(dir string, m metadata) error {
	b, err := json.MarshalIndent(m, "", "    ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "metadata.json"), append(b, '\n'), 0o644)
}

func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		return copyFile(path, target, info.Mode())
	})
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func downloadAndStage(owner, repo, commit, destDir string) error {
	tmp, err := os.MkdirTemp("", "millennium-theme-*")
	if err != nil {
		return fmt.Errorf("Error: Failed to create temporary directory for theme: %w", err)
	}
	defer os.RemoveAll(tmp)

	zipPath := filepath.Join(tmp, "theme.zip")
	url := githubapi.CommitZipURL(owner, repo, commit)
	fmt.Println("Downloading theme package...")
	if err := downloadURL(url, zipPath); err != nil {
		return fmt.Errorf("Error: theme download failed: %w", err)
	}
	if err := SafeExtractZip(zipPath, tmp); err != nil {
		return err
	}
	extracted := filepath.Join(tmp, fmt.Sprintf("%s-%s", repo, commit))
	if st, err := os.Stat(extracted); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Failed to extract theme archive.")
	}
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	if err := copyDir(extracted, destDir); err != nil {
		return err
	}
	return writeMetadata(destDir, metadata{Commit: commit, Owner: owner, Repo: repo})
}

// Install installs owner/repo into skins/<repo>.
func Install(ownerRepo string, dryRun bool) error {
	injectTokenFromConfig()
	owner, repo, err := ParseOwnerRepo(ownerRepo)
	if err != nil {
		return err
	}
	skins, err := SkinsDir()
	if err != nil {
		return err
	}
	target, err := ResolveThemeDir(skins, repo)
	if err != nil {
		return err
	}
	if st, err := os.Stat(target); err == nil && st.IsDir() {
		return fmt.Errorf("Warning: Theme directory '%s' already exists. Use update instead.", repo)
	}
	fmt.Printf("Resolving repository: %s/%s...\n", owner, repo)
	commit, err := themeLatestCommit(owner, repo)
	if err != nil || commit == "" {
		msg := fmt.Sprintf("Error: Could not retrieve latest commit info for %s/%s. Check repository name, network, or GitHub rate limits.", owner, repo)
		msg += "\nTip: set a PAT via millennium schedule config set github_token <token>."
		if err != nil {
			msg += fmt.Sprintf("\n(%v)", err)
		}
		return fmt.Errorf("%s", msg)
	}
	if dryRun {
		fmt.Printf("[DRY RUN] Would install %s/%s to %s\n", owner, repo, target)
		return nil
	}
	if err := os.MkdirAll(skins, 0o755); err != nil {
		return err
	}
	if err := downloadAndStage(owner, repo, commit, target); err != nil {
		_ = os.RemoveAll(target)
		return err
	}
	fmt.Printf("Successfully installed theme '%s'!\n", repo)
	fmt.Println("Next: enable it in Steam → Millennium → Themes (or Settings).")
	fmt.Println("Tip: millennium theme list shows installed themes; the active one is marked.")
	return nil
}

// UpdateOne updates a single installed theme by directory name.
func UpdateOne(themeName string, dryRun bool) error {
	injectTokenFromConfig()
	if err := SanitizeComponent(themeName, "theme name"); err != nil {
		return err
	}
	skins, err := SkinsDir()
	if err != nil {
		return err
	}
	target, err := ResolveThemeDir(skins, themeName)
	if err != nil {
		return err
	}
	if st, err := os.Stat(target); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Theme '%s' is not installed.", themeName)
	}
	metaPath := filepath.Join(target, "metadata.json")
	b, err := os.ReadFile(metaPath)
	if err != nil {
		fmt.Printf("Theme '%s' does not have GitHub metadata. Skipping.\n", themeName)
		return nil
	}
	var meta metadata
	if json.Unmarshal(b, &meta) != nil || meta.Owner == "" || meta.Repo == "" {
		return fmt.Errorf("Error: Invalid metadata format in %s.", metaPath)
	}
	if err := SanitizeComponent(meta.Owner, "theme owner"); err != nil {
		return err
	}
	if err := SanitizeComponent(meta.Repo, "theme repo"); err != nil {
		return err
	}
	fmt.Printf("Checking updates for theme '%s' (%s/%s)...\n", themeName, meta.Owner, meta.Repo)
	commit, err := themeLatestCommit(meta.Owner, meta.Repo)
	if err != nil || commit == "" {
		return fmt.Errorf("Error: Could not retrieve latest commit info from GitHub.")
	}
	if meta.Commit == commit {
		fmt.Printf("Theme '%s' is already up to date.\n", themeName)
		return nil
	}
	short := commit
	if len(short) > 7 {
		short = short[:7]
	}
	fmt.Printf("New commit found: %s. Updating...\n", short)
	if dryRun {
		fmt.Printf("[DRY RUN] Would update theme '%s' to commit %s\n", themeName, commit)
		return nil
	}
	tmpDir := target + ".tmp"
	bakDir := target + ".bak"
	_ = os.RemoveAll(tmpDir)
	_ = os.RemoveAll(bakDir)
	if err := downloadAndStage(meta.Owner, meta.Repo, commit, tmpDir); err != nil {
		_ = os.RemoveAll(tmpDir)
		return err
	}
	if err := os.Rename(target, bakDir); err != nil {
		_ = os.RemoveAll(tmpDir)
		return err
	}
	if err := os.Rename(tmpDir, target); err != nil {
		_ = os.Rename(bakDir, target)
		_ = os.RemoveAll(tmpDir)
		return err
	}
	_ = os.RemoveAll(bakDir)
	fmt.Printf("Successfully updated theme '%s' to commit %s!\n", themeName, short)
	return nil
}

// UpdateAll updates every installed theme directory.
func UpdateAll(dryRun bool) error {
	skins, err := SkinsDir()
	if err != nil {
		return err
	}
	fmt.Println("=== Updating All Installed Themes ===")
	entries, err := os.ReadDir(skins)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Printf("No themes skins directory found at %s.\n", skins)
			return nil
		}
		return err
	}
	found := false
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		found = true
		_ = UpdateOne(e.Name(), dryRun)
		fmt.Println()
	}
	if !found {
		fmt.Println("No themes installed.")
		fmt.Println("Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin")
	}
	return nil
}

// Remove deletes an installed theme directory.
func Remove(themeName string, yes, dryRun bool) error {
	if err := SanitizeComponent(themeName, "theme name"); err != nil {
		return err
	}
	skins, err := SkinsDir()
	if err != nil {
		return err
	}
	target, err := ResolveThemeDir(skins, themeName)
	if err != nil {
		return err
	}
	if st, err := os.Stat(target); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Theme '%s' is not installed.", themeName)
	}
	if ActiveThemeName() == themeName {
		fmt.Printf("Warning: '%s' is currently the active Millennium theme.\n", themeName)
	}
	if dryRun {
		fmt.Printf("[DRY RUN] Would remove theme '%s' (%s)\n", themeName, target)
		return nil
	}
	if err := confirmRemove(themeName, yes); err != nil {
		return err
	}
	fmt.Printf("Removing theme '%s'...\n", themeName)
	if err := os.RemoveAll(target); err != nil {
		return err
	}
	fmt.Printf("Theme '%s' successfully removed.\n", themeName)
	return nil
}

func confirmRemove(themeName string, yes bool) error {
	if yes || os.Getenv("TEST_SUITE_RUN") != "" {
		return nil
	}
	fi, err := os.Stdin.Stat()
	if err != nil || (fi.Mode()&os.ModeCharDevice) == 0 {
		return fmt.Errorf("Error: Refusing to remove theme without confirmation in a non-interactive session.\nRe-run with --yes (or -y), or use --dry-run.")
	}
	fmt.Fprintf(os.Stderr, "Remove theme '%s'? [y/N]: ", themeName)
	var resp string
	_, _ = fmt.Fscanln(os.Stdin, &resp)
	if !strings.EqualFold(resp, "y") && !strings.EqualFold(resp, "yes") {
		return fmt.Errorf("Aborted.")
	}
	return nil
}
