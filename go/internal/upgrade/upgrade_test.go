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
	if runtime.GOOS == "windows" {
		t.Setenv("MILLENNIUM_BACKUP_DIR", root)
		if err := os.Mkdir(filepath.Join(root, "20260101_120000"), 0o755); err != nil {
			t.Fatal(err)
		}
	} else {
		t.Setenv("MOCK_LIB_DIR", root)
		if err := os.Mkdir(filepath.Join(root, "millennium.bak_20260101"), 0o755); err != nil {
			t.Fatal(err)
		}
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

func TestNeedsLegacyAlwaysFalse(t *testing.T) {
	cases := []Options{
		{},
		{LocalFile: "/tmp/a.tgz"},
		{Rollback: true, RollbackTarget: "1"},
		{DryRun: true},
	}
	for _, o := range cases {
		if NeedsLegacy(o) {
			t.Fatalf("NeedsLegacy(%+v) = true; expected false", o)
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
	if runtime.GOOS == "windows" {
		t.Setenv("MILLENNIUM_BACKUP_DIR", root)
		_ = os.Mkdir(filepath.Join(root, "x"), 0o755)
	} else {
		t.Setenv("MOCK_LIB_DIR", root)
		_ = os.Mkdir(filepath.Join(root, "millennium.bak_x"), 0o755)
	}
	o := Options{Rollback: true, RollbackTarget: "list"}
	handled, code := RunNative(o)
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
}

func TestResolveBackupName(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix backup names")
	}
	root := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", root)
	t.Setenv("MILLENNIUM_LIB_DIR", root)
	_ = os.Mkdir(filepath.Join(root, "millennium.bak_aaa"), 0o755)
	_ = os.Mkdir(filepath.Join(root, "millennium.bak_bbb"), 0o755)
	got, err := ResolveBackupName("bbb")
	if err != nil || got != "millennium.bak_bbb" {
		t.Fatalf("got=%s err=%v", got, err)
	}
	got, err = ResolveBackupName("")
	if err != nil || got != "millennium.bak_bbb" {
		t.Fatalf("default=%s err=%v", got, err)
	}
	if _, err := ResolveBackupName("missing"); err == nil {
		t.Fatal("expected missing")
	}
}

func TestApplyRollbackUnix(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix rollback")
	}
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)

	active := filepath.Join(lib, "millennium")
	bak := filepath.Join(lib, "millennium.bak_1.0.0")
	_ = os.MkdirAll(active, 0o755)
	_ = os.MkdirAll(bak, 0o755)
	_ = os.WriteFile(filepath.Join(active, "version.txt"), []byte("2.0.0\n"), 0o644)
	_ = os.WriteFile(filepath.Join(active, "marker"), []byte("new"), 0o644)
	_ = os.WriteFile(filepath.Join(bak, "version.txt"), []byte("1.0.0\n"), 0o644)
	_ = os.WriteFile(filepath.Join(bak, "marker"), []byte("old"), 0o644)

	o := Options{Rollback: true, RollbackTarget: "1.0.0", Quiet: true}
	handled, code := RunNative(o)
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
	marker, err := os.ReadFile(filepath.Join(lib, "millennium", "marker"))
	if err != nil || string(marker) != "old" {
		t.Fatalf("marker=%s err=%v", marker, err)
	}
	saved := filepath.Join(lib, "millennium.bak_2.0.0")
	if st, err := os.Stat(saved); err != nil || !st.IsDir() {
		t.Fatalf("expected saved prior install: %v", err)
	}
	if _, err := os.Stat(bak); !os.IsNotExist(err) {
		t.Fatal("consumed backup should be gone")
	}
}

func TestApplyRollbackDryRun(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix rollback dry-run")
	}
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)
	_ = os.Mkdir(filepath.Join(lib, "millennium.bak_x"), 0o755)
	_ = os.Mkdir(filepath.Join(lib, "millennium"), 0o755)
	o := Options{Rollback: true, RollbackTarget: "x", DryRun: true}
	handled, code := RunNative(o)
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
	if _, err := os.Stat(filepath.Join(lib, "millennium.bak_x")); err != nil {
		t.Fatal("dry-run must not consume backup")
	}
}

func TestNeedsLegacyRollback(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix writability via MOCK_LIB_DIR")
	}
	lib := t.TempDir()
	t.Setenv("MOCK_LIB_DIR", lib)
	t.Setenv("MILLENNIUM_LIB_DIR", lib)
	if NeedsLegacy(Options{Rollback: true, RollbackTarget: "1"}) {
		t.Fatal("NeedsLegacy must stay false")
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
