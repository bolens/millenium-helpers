package upgrade

import (
	"strings"
	"testing"
)

func TestBuildSudoUpgradeArgs(t *testing.T) {
	o := Options{Channel: "beta", Force: true, Yes: true, Quiet: true, AllUsers: true}
	got := BuildSudoUpgradeArgs("/usr/bin/millennium", o, "/tmp/a.tgz", "deadbeef")
	want := []string{
		"/usr/bin/millennium", "upgrade",
		"--channel", "beta", "--force", "--yes", "--quiet", "--all-users",
		"--file", "/tmp/a.tgz", "--sha256", "deadbeef",
	}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("got %v", got)
	}
}

func TestBuildSudoRollbackArgs(t *testing.T) {
	got := BuildSudoRollbackArgs("/bin/millennium", Options{RollbackTarget: "1.2.3", DryRun: true})
	if strings.Join(got, " ") != "/bin/millennium upgrade --rollback 1.2.3 --dry-run" {
		t.Fatalf("%v", got)
	}
}

func TestFormatSudoInstallHint(t *testing.T) {
	h := FormatSudoInstallHint("/tmp/x.tgz", "abc", Options{Channel: "stable", Force: true})
	if !strings.Contains(h, "sudo millennium upgrade --file /tmp/x.tgz --sha256 abc") {
		t.Fatalf("%s", h)
	}
}

func TestTrySudoInstallHandoffSkippedWhenWritable(t *testing.T) {
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)
	handled, code := TrySudoInstallHandoff(Options{}, "/tmp/a.tgz", "aa")
	if handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
}

func TestTrySudoInstallHandoffMock(t *testing.T) {
	if !NeedsSudoHandoff() {
		t.Skip("sudo handoff not required in this environment")
	}
	var saw []string
	origLook, origRun, origExe := sudoLookPath, sudoRun, osExecutable
	sudoLookPath = func(file string) (string, error) { return "/usr/bin/sudo", nil }
	sudoRun = func(args []string) int {
		saw = append([]string(nil), args...)
		return 0
	}
	osExecutable = func() (string, error) { return "/opt/millennium", nil }
	t.Cleanup(func() {
		sudoLookPath = origLook
		sudoRun = origRun
		osExecutable = origExe
	})
	handled, code := TrySudoInstallHandoff(Options{Channel: "stable", Quiet: true}, "/tmp/archive.tgz", "aa")
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
	if len(saw) < 4 || saw[0] != "/opt/millennium" || saw[1] != "upgrade" {
		t.Fatalf("%v", saw)
	}
}

func TestNeedsSudoHandoffRespectsOverride(t *testing.T) {
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)
	if NeedsSudoHandoff() {
		t.Fatal("custom writable lib should not need sudo handoff")
	}
}
