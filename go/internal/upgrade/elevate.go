package upgrade

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// Test seams
var (
	sudoLookPath = exec.LookPath
	sudoRun      = runSudo
	osExecutable = os.Executable
)

// NeedsSudoHandoff is true when Linux system install needs elevation and no
// custom lib override is in play (custom dirs should fail clearly, not sudo).
func NeedsSudoHandoff() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	if os.Getenv("MILLENNIUM_LIB_DIR") != "" || os.Getenv("MOCK_LIB_DIR") != "" {
		return false
	}
	return !CanNativeInstall()
}

// BuildSudoUpgradeArgs builds argv for: sudo <exe> upgrade …
func BuildSudoUpgradeArgs(exe string, o Options, archivePath, sha string) []string {
	args := []string{exe, "upgrade"}
	if o.Channel != "" && o.Channel != "stable" {
		args = append(args, "--channel", o.Channel)
	} else if o.Channel == "stable" {
		args = append(args, "--channel", "stable")
	}
	if o.Force {
		args = append(args, "--force")
	}
	if o.Yes {
		args = append(args, "--yes")
	}
	if o.Quiet {
		args = append(args, "--quiet")
	}
	if o.AllUsers {
		args = append(args, "--all-users")
	}
	if archivePath != "" {
		args = append(args, "--file", archivePath)
		if sha != "" {
			args = append(args, "--sha256", sha)
		} else if o.InsecureSkipVerify {
			args = append(args, "--insecure-skip-verify")
		}
	}
	return args
}

// BuildSudoRollbackArgs builds argv for: sudo <exe> upgrade --rollback <id>
func BuildSudoRollbackArgs(exe string, o Options) []string {
	args := []string{exe, "upgrade", "--rollback"}
	if o.RollbackTarget != "" {
		args = append(args, o.RollbackTarget)
	}
	if o.Yes {
		args = append(args, "--yes")
	}
	if o.Quiet {
		args = append(args, "--quiet")
	}
	if o.DryRun {
		args = append(args, "--dry-run")
	}
	return args
}

// FormatSudoInstallHint prints how to finish a verified non-root download.
func FormatSudoInstallHint(archivePath, sha string, o Options) string {
	var b strings.Builder
	b.WriteString("Error: installing Millennium to /usr/lib requires root.\n")
	b.WriteString("Re-run with sudo (archive already verified):\n  ")
	b.WriteString("sudo millennium upgrade")
	if archivePath != "" {
		b.WriteString(" --file ")
		b.WriteString(archivePath)
		if sha != "" {
			b.WriteString(" --sha256 ")
			b.WriteString(sha)
		} else if o.InsecureSkipVerify {
			b.WriteString(" --insecure-skip-verify")
		}
	}
	if o.Channel != "" {
		b.WriteString(" --channel ")
		b.WriteString(o.Channel)
	}
	if o.Force {
		b.WriteString(" --force")
	}
	b.WriteByte('\n')
	return b.String()
}

// TrySudoInstallHandoff re-execs under sudo with a verified local archive.
// Returns handled=true whenever elevation was attempted or required.
func TrySudoInstallHandoff(o Options, archivePath, sha string) (handled bool, code int) {
	if !NeedsSudoHandoff() || archivePath == "" {
		return false, 0
	}
	if sha == "" {
		sha = o.LocalSHA
	}
	exe, err := osExecutable()
	if err != nil || exe == "" {
		fmt.Fprint(os.Stderr, FormatSudoInstallHint(archivePath, sha, o))
		return true, 1
	}
	if _, err := sudoLookPath("sudo"); err != nil {
		fmt.Fprint(os.Stderr, FormatSudoInstallHint(archivePath, sha, o))
		fmt.Fprintln(os.Stderr, "Hint: install sudo, or re-run as root.")
		return true, 1
	}
	args := BuildSudoUpgradeArgs(exe, o, archivePath, sha)
	if !o.Quiet {
		fmt.Println("Install requires root; elevating with sudo…")
	}
	code = sudoRun(args)
	if code != 0 {
		fmt.Fprint(os.Stderr, FormatSudoInstallHint(archivePath, sha, o))
	}
	return true, code
}

// TrySudoRollbackHandoff re-execs rollback under sudo when /usr/lib is not writable.
func TrySudoRollbackHandoff(o Options) (handled bool, code int) {
	if !o.Rollback || !NeedsSudoHandoff() {
		return false, 0
	}
	exe, err := osExecutable()
	if err != nil || exe == "" {
		fmt.Fprintln(os.Stderr, "Error: rollback requires root. Re-run: sudo millennium upgrade --rollback", o.RollbackTarget)
		return true, 1
	}
	if _, err := sudoLookPath("sudo"); err != nil {
		fmt.Fprintln(os.Stderr, "Error: rollback requires root (sudo not found).")
		return true, 1
	}
	if !o.Quiet {
		fmt.Println("Rollback requires root; elevating with sudo…")
	}
	return true, sudoRun(BuildSudoRollbackArgs(exe, o))
}

func runSudo(args []string) int {
	// Prefer passwordless; fall back to interactive sudo (prompts on TTY).
	nonInteractive := append([]string{"-n"}, args...)
	cmd := exec.Command("sudo", nonInteractive...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err == nil {
		return 0
	}
	cmd = exec.Command("sudo", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		return 1
	}
	return 0
}
