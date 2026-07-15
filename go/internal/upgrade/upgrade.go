package upgrade

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/githubapi"
)

// Options holds parsed upgrade CLI flags.
type Options struct {
	Channel            string
	Force              bool
	DryRun             bool
	Quiet              bool
	Yes                bool
	Rollback           bool
	RollbackTarget     string
	LocalFile          string
	LocalSHA           string
	InsecureSkipVerify bool
	AllUsers           bool
	Help               bool
	Version            bool
}

// LibDir returns the Millennium lib/backup root (overridable for tests).
func LibDir() string {
	if d := os.Getenv("MOCK_LIB_DIR"); d != "" {
		return d
	}
	if d := os.Getenv("MILLENNIUM_LIB_DIR"); d != "" {
		return d
	}
	if runtime.GOOS == "windows" {
		// Windows backups live under helpers install; leave empty for listing via BackupDir.
		return ""
	}
	return "/usr/lib"
}

// BackupDir returns Windows-style backup parent when set.
func BackupDir() string {
	if d := os.Getenv("MILLENNIUM_BACKUP_DIR"); d != "" {
		return d
	}
	return ""
}

// ParseArgs parses upgrade argv (GNU + common Windows aliases).
func ParseArgs(args []string) (Options, error) {
	var o Options
	o.Channel = "stable"
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "-h", "--help", "-Help":
			o.Help = true
		case "-V", "--version", "-Version":
			o.Version = true
		case "-f", "--force", "-Force":
			o.Force = true
		case "-y", "--yes", "-Yes":
			o.Yes = true
		case "-d", "--dry-run", "-DryRun":
			o.DryRun = true
		case "-q", "--quiet", "-Quiet":
			o.Quiet = true
		case "--stable":
			o.Channel = "stable"
		case "--beta":
			o.Channel = "beta"
		case "--main":
			o.Channel = "main"
		case "--all-users":
			o.AllUsers = true
		case "--insecure-skip-verify", "-InsecureSkipVerify":
			o.InsecureSkipVerify = true
		case "-c", "--channel", "-Channel":
			if i+1 >= len(args) {
				return o, fmt.Errorf("Error: --channel requires an argument (stable/beta/main).")
			}
			i++
			o.Channel = args[i]
			if o.Channel != "stable" && o.Channel != "beta" && o.Channel != "main" {
				return o, fmt.Errorf("Error: Invalid channel '%s'. Must be stable, beta, or main.", o.Channel)
			}
		case "--file", "-File":
			if i+1 >= len(args) {
				return o, fmt.Errorf("Error: --file requires a path.")
			}
			i++
			o.LocalFile = args[i]
		case "--sha256", "-Sha256":
			if i+1 >= len(args) {
				return o, fmt.Errorf("Error: --sha256 requires a hex digest.")
			}
			i++
			o.LocalSHA = args[i]
		case "-r", "--rollback", "-Rollback":
			o.Rollback = true
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				i++
				o.RollbackTarget = args[i]
			}
		default:
			return o, fmt.Errorf("Error: unknown option %s", a)
		}
	}
	return o, nil
}

// ListBackups returns backup directory basenames (Unix millennium.bak_* style, or Windows backup dir entries).
func ListBackups() ([]string, error) {
	if runtime.GOOS == "windows" || BackupDir() != "" {
		dir := EffectiveBackupDir()
		if dir == "" {
			return nil, nil
		}
		entries, err := os.ReadDir(dir)
		if err != nil {
			if os.IsNotExist(err) {
				return nil, nil
			}
			return nil, err
		}
		var out []string
		for _, e := range entries {
			if e.IsDir() {
				out = append(out, e.Name())
			}
		}
		sort.Strings(out)
		return out, nil
	}
	lib := LibDir()
	var out []string
	matches, _ := filepath.Glob(filepath.Join(lib, "millennium.bak_*"))
	for _, m := range matches {
		if st, err := os.Stat(m); err == nil && st.IsDir() {
			out = append(out, filepath.Base(m))
		}
	}
	if st, err := os.Stat(filepath.Join(lib, "millennium.bak")); err == nil && st.IsDir() {
		out = append(out, "millennium.bak")
	}
	sort.Strings(out)
	return out, nil
}

// FormatBackupList matches shell messaging for --rollback list.
func FormatBackupList(backups []string) string {
	var b strings.Builder
	b.WriteString("Available Backups:\n")
	if len(backups) == 0 {
		b.WriteString("  No backups found.\n")
	} else {
		for _, name := range backups {
			label := strings.TrimPrefix(name, "millennium.bak_")
			if name == "millennium.bak" {
				label = "Legacy Backup (millennium.bak)"
			}
			b.WriteString("  - " + label + "\n")
		}
	}
	b.WriteString("\n")
	b.WriteString("Apply one with: millennium upgrade --rollback <id>\n")
	b.WriteString("  (Windows: millennium upgrade -Rollback <id>)\n")
	return b.String()
}

// VerifyFileSHA256 checks path against expected hex digest (64 hex chars).
func VerifyFileSHA256(path, expectedHex string) error {
	expectedHex = strings.ToLower(strings.TrimSpace(expectedHex))
	if len(expectedHex) != 64 {
		return fmt.Errorf("Error: --sha256 must be 64 hex characters.")
	}
	if _, err := hex.DecodeString(expectedHex); err != nil {
		return fmt.Errorf("Error: --sha256 must be 64 hex characters.")
	}
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("Error: cannot open archive: %w", err)
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("Error: failed hashing archive: %w", err)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if got != expectedHex {
		return fmt.Errorf("Error: SHA256 mismatch for %s (got %s, expected %s).", path, got, expectedHex)
	}
	return nil
}

// NeedsLegacy reports whether this invocation must run the shell/PS upgrade path.
// Always false — install/rollback are native (+ Linux sudo handoff).
func NeedsLegacy(o Options) bool {
	return false
}

// RunNative handles help/version/rollback-list/dry-run and pre-verify. Returns handled=true when done.
func RunNative(o Options) (handled bool, code int) {
	if o.Help {
		fmt.Print(`Usage: millennium upgrade [OPTIONS]

Install official Millennium (stable, beta, or main) releases.

Options:
  -c, --channel CHANNEL  Update channel: stable, beta, or main
  --stable|--beta|--main
  -r, --rollback [ID]    Roll back (or pass "list")
  --file PATH            Install from a local archive
  --sha256 HEX           Expected SHA256 of --file
  --insecure-skip-verify Allow --file without checksum
  --all-users            Linux/macOS multi-user hooks
  -f, --force  -y, --yes  -d, --dry-run  -q, --quiet
  -V, --version  -h, --help

Native: --rollback list|apply (when writable), --dry-run (resolve/verify/rollback),
remote download+SHA, --file SHA pre-check, live extract/install when writable
(root / MILLENNIUM_LIB_DIR / Windows Steam). On Linux, non-root downloads verify
then re-exec via sudo for install/rollback.
`)
		return true, 0
	}
	if o.Version {
		return false, 0
	}
	if o.Rollback && o.RollbackTarget == "list" {
		backs, err := ListBackups()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return true, 1
		}
		fmt.Print(FormatBackupList(backs))
		return true, 0
	}
	if o.Rollback {
		if !CanNativeRollback() {
			return false, 0
		}
		return true, applyRollback(o)
	}
	if o.DryRun {
		code := runDryRun(o)
		return true, code
	}
	if o.LocalFile != "" && o.LocalSHA != "" {
		if err := VerifyFileSHA256(o.LocalFile, o.LocalSHA); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			return true, 1
		}
	}
	if o.LocalFile != "" && o.LocalSHA == "" && !o.InsecureSkipVerify {
		fmt.Fprintln(os.Stderr, "Error: --file requires --sha256 (or --insecure-skip-verify).")
		return true, 1
	}
	return false, 0
}

func runDryRun(o Options) int {
	fmt.Println("=== DRY RUN MODE: No changes will be made ===")
	if o.LocalFile != "" {
		if _, err := os.Stat(o.LocalFile); err != nil {
			fmt.Fprintf(os.Stderr, "Error: local archive not found: %s\n", o.LocalFile)
			return 1
		}
		if o.LocalSHA != "" {
			if err := VerifyFileSHA256(o.LocalFile, o.LocalSHA); err != nil {
				fmt.Fprintln(os.Stderr, err.Error())
				return 1
			}
			fmt.Printf("[DRY RUN] Verified SHA256 for %s\n", o.LocalFile)
		} else if !o.InsecureSkipVerify {
			fmt.Fprintln(os.Stderr, "Error: --file requires --sha256 (or --insecure-skip-verify).")
			return 1
		} else {
			fmt.Printf("[DRY RUN] Would install from %s without checksum verification\n", o.LocalFile)
		}
		fmt.Printf("[DRY RUN] Would install local archive on channel %s (force=%v)\n", o.Channel, o.Force)
		fmt.Println("[DRY RUN] Would clear /usr/lib/millennium/* and install new binaries")
		return 0
	}

	meta, err := ResolveRemoteRelease(o)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	if meta.UpToDate {
		fmt.Printf("Millennium is already up to date (v%s). Use --force to reinstall.\n", meta.Version)
		return 0
	}
	fmt.Printf("Resolved tag: %s\n", meta.Tag)
	fmt.Printf("[DRY RUN] Would download archive: %s\n", meta.ArchiveURL)
	fmt.Printf("[DRY RUN] Expected SHA256: %s\n", meta.SHA)
	fmt.Println("[DRY RUN] Would clear /usr/lib/millennium/* and install new binaries")
	fmt.Println("[DRY RUN] Would install Millennium MIT LICENSE into /usr/lib/millennium/")
	return 0
}

// ReleaseMeta describes a resolved GitHub release archive.
type ReleaseMeta struct {
	Tag        string
	Version    string
	ArchiveURL string
	SHAURL     string
	SHA        string
	Archive    string
	UpToDate   bool
}

// ResolveRemoteRelease looks up tag + checksum (and up-to-date short-circuit).
func ResolveRemoteRelease(o Options) (ReleaseMeta, error) {
	injectTokenFromConfig()
	fmt.Printf("Fetching latest Millennium %s release tag...\n", o.Channel)
	tag, err := githubapi.LatestTag(o.Channel)
	if err != nil || tag == "" {
		msg := fmt.Sprintf("Error: Could not retrieve the latest %s version tag from GitHub.\nIf you are rate-limited, set a PAT: millennium schedule config set github_token <token>", o.Channel)
		if err != nil {
			msg += fmt.Sprintf("\n(%v)", err)
		}
		return ReleaseMeta{}, fmt.Errorf("%s", msg)
	}
	ver := strings.TrimPrefix(tag, "v")
	meta := ReleaseMeta{Tag: tag, Version: ver}

	if !o.Force && runtime.GOOS != "windows" {
		if b, err := os.ReadFile("/usr/lib/millennium/version.txt"); err == nil {
			installed := strings.TrimSpace(string(b))
			if installed == ver {
				meta.UpToDate = true
				return meta, nil
			}
		}
	}

	var archive, shaName string
	if runtime.GOOS == "windows" {
		archive, shaName = githubapi.WindowsArchiveNames(ver)
	} else {
		archive, shaName = githubapi.LinuxArchiveNames(ver)
	}
	meta.Archive = archive
	meta.ArchiveURL = githubapi.ReleaseDownloadURL(tag, archive)
	meta.SHAURL = githubapi.ReleaseDownloadURL(tag, shaName)
	fmt.Printf("Fetching SHA256 checksum for Millennium v%s...\n", ver)
	sha, err := githubapi.FetchFirstFieldSHA(meta.SHAURL)
	if err != nil || sha == "" {
		msg := fmt.Sprintf("Error: Could not retrieve the SHA256 checksum for v%s.", ver)
		if err != nil {
			msg += fmt.Sprintf("\n(%v)", err)
		}
		return ReleaseMeta{}, fmt.Errorf("%s", msg)
	}
	meta.SHA = sha
	return meta, nil
}

// FetchRemoteArchive downloads and verifies a channel release.
// Returns empty path when already up to date (no download).
func FetchRemoteArchive(o Options) (path, sha, tag string, err error) {
	meta, err := ResolveRemoteRelease(o)
	if err != nil {
		return "", "", "", err
	}
	if meta.UpToDate {
		fmt.Printf("Millennium is already up to date (v%s). Use --force to reinstall.\n", meta.Version)
		return "", "", meta.Tag, nil
	}
	fmt.Printf("Resolved tag: %s\n", meta.Tag)
	tmp, err := os.CreateTemp("", "millennium-dl-*")
	if err != nil {
		return "", "", "", fmt.Errorf("Error: cannot create temp file: %w", err)
	}
	path = tmp.Name()
	_ = tmp.Close()
	// Prefer archive basename suffix for legacy recognition.
	dest := filepath.Join(filepath.Dir(path), meta.Archive)
	_ = os.Remove(path)
	fmt.Printf("Downloading %s…\n", meta.ArchiveURL)
	if err := githubapi.Download(meta.ArchiveURL, dest); err != nil {
		_ = os.Remove(dest)
		return "", "", "", fmt.Errorf("Error: download failed: %w", err)
	}
	if err := VerifyFileSHA256(dest, meta.SHA); err != nil {
		_ = os.Remove(dest)
		return "", "", "", err
	}
	fmt.Printf("Verified SHA256 for %s\n", dest)
	return dest, meta.SHA, meta.Tag, nil
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
