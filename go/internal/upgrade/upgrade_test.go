package upgrade

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func TestParseChannel(t *testing.T) {
	o, err := ParseArgs([]string{"--channel", "beta", "--force"})
	if err != nil {
		t.Fatal(err)
	}
	if o.Channel != "beta" || !o.Force {
		t.Fatalf("%+v", o)
	}
	_, err = ParseArgs([]string{"--channel", "nope"})
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestListBackupsAndFormat(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", root)
	if err := os.Mkdir(filepath.Join(root, "millennium.bak_20260101"), 0o755); err != nil {
		t.Fatal(err)
	}
	backs, err := ListBackups()
	if err != nil || len(backs) != 1 {
		t.Fatalf("%v %v", backs, err)
	}
	out := FormatBackupList(backs)
	if !contains(out, "20260101") {
		t.Fatalf("%s", out)
	}
}

func TestVerifyFileSHA256(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "a.tar.gz")
	content := []byte("hello-millennium")
	if err := os.WriteFile(p, content, 0o644); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(content)
	hexSum := hex.EncodeToString(sum[:])
	if err := VerifyFileSHA256(p, hexSum); err != nil {
		t.Fatal(err)
	}
	if err := VerifyFileSHA256(p, "0000000000000000000000000000000000000000000000000000000000000000"); err == nil {
		t.Fatal("expected mismatch")
	}
}

func TestArgsForLocalFile(t *testing.T) {
	got := ArgsForLocalFile([]string{"--channel", "beta", "--file", "old.tgz", "--sha256", "abc"}, "/tmp/n.tgz", "deadbeef")
	wantSuffix := []string{"--file", "/tmp/n.tgz", "--sha256", "deadbeef"}
	if len(got) < 5 || got[0] != "--channel" || got[1] != "beta" {
		t.Fatalf("%v", got)
	}
	for i, w := range wantSuffix {
		if got[len(got)-len(wantSuffix)+i] != w {
			t.Fatalf("suffix: %v", got)
		}
	}
}

func TestRunNativeRollbackList(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", root)
	_ = os.Mkdir(filepath.Join(root, "millennium.bak_x"), 0o755)
	o := Options{Rollback: true, RollbackTarget: "list"}
	handled, code := RunNative(o)
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
