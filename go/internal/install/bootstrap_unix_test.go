//go:build unix

package install

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// install.sh is a thin bootstrap over `millennium install`. These checks keep
// the hand-off contract covered in Go (replacing tests/behavioral/test_install.sh).
func TestInstallShBootstrap(t *testing.T) {
	root := repoRoot(t)
	installSh := filepath.Join(root, "install.sh")
	if _, err := os.Stat(installSh); err != nil {
		t.Fatal(err)
	}
	verBytes, err := os.ReadFile(filepath.Join(root, "VERSION"))
	if err != nil {
		t.Fatal(err)
	}
	ver := strings.TrimSpace(string(verBytes))
	exe := filepath.Join(t.TempDir(), "millennium")
	cmd := exec.Command(
		"go", "build", "-buildvcs=false",
		"-ldflags", "-X github.com/bolens/millenium-helpers/internal/version.Version="+ver,
		"-o", exe, "./cmd/millennium",
	)
	cmd.Dir = filepath.Join(root, "go")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}

	runInstallSh := func(args ...string) ([]byte, error) {
		t.Helper()
		cmd := exec.Command("bash", append([]string{installSh}, args...)...)
		cmd.Env = append(os.Environ(), "MILLENNIUM_BOOTSTRAP_BIN="+exe)
		return cmd.CombinedOutput()
	}
	help, err := runInstallSh("--help")
	if err != nil {
		t.Fatalf("install.sh --help: %v\n%s", err, help)
	}
	text := string(help)
	if !strings.Contains(text, "millennium install") || !strings.Contains(text, "--track") {
		t.Fatalf("install.sh --help missing expected text:\n%s", text)
	}

	vout, err := runInstallSh("--version")
	if err != nil {
		t.Fatalf("install.sh --version: %v\n%s", err, vout)
	}
	if !strings.Contains(string(vout), ver) {
		t.Fatalf("install.sh --version want %q got:\n%s", ver, vout)
	}

	prefix := t.TempDir()
	dry, err := runInstallSh(
		"install",
		"--dry-run",
		"--prefix", filepath.Join(prefix, "bin"),
		"--lib-dir", filepath.Join(prefix, "lib"),
		"--skip-wizard",
	)
	if err != nil {
		t.Fatalf("install.sh install --dry-run: %v\n%s", err, dry)
	}
	if !strings.Contains(string(dry), "DRY RUN MODE") {
		t.Fatalf("expected dry-run banner:\n%s", dry)
	}
	if _, err := os.Stat(filepath.Join(prefix, "bin", "millennium")); !os.IsNotExist(err) {
		t.Fatalf("dry-run wrote binary: %v", err)
	}
}
