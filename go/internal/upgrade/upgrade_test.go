package upgrade

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"runtime"
	"strings"
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

func TestInferVersion(t *testing.T) {
	if got := InferVersion("/tmp/millennium-v2.30.0-linux-x86_64.tar.gz", ""); got != "2.30.0" {
		t.Fatalf("%s", got)
	}
}

func TestNativeInstallUnix(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix install test")
	}
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)
	home := t.TempDir()
	t.Setenv("HOME", home)
	steam := filepath.Join(home, ".local", "share", "Steam")
	_ = os.MkdirAll(filepath.Join(steam, "ubuntu12_32"), 0o755)
	_ = os.MkdirAll(filepath.Join(steam, "ubuntu12_64"), 0o755)
	t.Setenv("STEAM", steam)

	archive := filepath.Join(t.TempDir(), "millennium-v9.9.9-linux-x86_64.tar.gz")
	if err := writeTestTarGz(archive); err != nil {
		t.Fatal(err)
	}
	o := Options{Channel: "stable", Quiet: true}
	handled, code := TryNativeInstall(o, archive, "9.9.9")
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
	ver, err := os.ReadFile(filepath.Join(lib, "millennium", "version.txt"))
	if err != nil || strings.TrimSpace(string(ver)) != "9.9.9" {
		t.Fatalf("%s %v", ver, err)
	}
	if _, err := os.Stat(filepath.Join(lib, "millennium", "LICENSE")); err != nil {
		t.Fatal(err)
	}
}

func writeTestTarGz(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	add := func(name, body string, mode int64) error {
		hdr := &tar.Header{Name: name, Mode: mode, Size: int64(len(body))}
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		_, err := tw.Write([]byte(body))
		return err
	}
	files := []string{
		"usr/lib/millennium/libmillennium_bootstrap_x86.so",
		"usr/lib/millennium/libmillennium_bootstrap_hhx64.so",
		"usr/lib/millennium/libmillennium_x86.so",
		"usr/lib/millennium/libmillennium_hhx64.so",
		"usr/lib/millennium/libmillennium_pvs64",
	}
	for _, n := range files {
		if err := add(n, "binary-"+filepath.Base(n), 0o755); err != nil {
			return err
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	return gz.Close()
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
