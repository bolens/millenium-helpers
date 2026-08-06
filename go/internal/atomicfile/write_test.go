package atomicfile

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestWriteFileReplacesContentAndMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(path, []byte("new"), 0o600); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != "new" {
		t.Fatalf("got %q", body)
	}
	if runtime.GOOS != "windows" {
		if st, err := os.Stat(path); err != nil {
			t.Fatal(err)
		} else if st.Mode().Perm() != 0o600 {
			t.Fatalf("mode=%o", st.Mode().Perm())
		}
	}
}
