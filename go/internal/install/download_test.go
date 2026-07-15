package install

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestFetchHelpersTreeWithSHA(t *testing.T) {
	payloadDir := t.TempDir()
	archivePath := filepath.Join(payloadDir, "helpers.tar.gz")
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	body := "fake-millennium\n"
	entries := []struct {
		name string
		data string
		mode int64
	}{
		{"pack/VERSION", "9.9.9\n", 0o644},
		{"pack/bin/millennium", body, 0o755},
	}
	if runtime.GOOS == "windows" {
		entries = []struct {
			name string
			data string
			mode int64
		}{
			{"pack/VERSION", "9.9.9\n", 0o644},
			{"pack/bin/millennium.exe", body, 0o755},
		}
	}
	for _, e := range entries {
		hdr := &tar.Header{Name: e.name, Mode: e.mode, Size: int64(len(e.data))}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(e.data)); err != nil {
			t.Fatal(err)
		}
	}
	_ = tw.Close()
	_ = gz.Close()
	_ = f.Close()

	raw, err := os.ReadFile(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(raw)
	shaHex := hex.EncodeToString(sum[:])

	mux := http.NewServeMux()
	mux.HandleFunc("/helpers.tar.gz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(raw)
	})
	mux.HandleFunc("/helpers.tar.gz.sha256", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(shaHex + "  helpers.tar.gz\n"))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	t.Setenv("MILLENNIUM_HELPERS_RELEASE_URL", srv.URL+"/helpers.tar.gz")
	t.Setenv("MILLENNIUM_HELPERS_RELEASE_SHA_URL", srv.URL+"/helpers.tar.gz.sha256")

	root, tmp, resolved, err := FetchHelpersTree(Options{Track: "release", Tag: ""})
	if tmp != "" {
		t.Cleanup(func() { _ = os.RemoveAll(tmp) })
	}
	if err != nil {
		t.Fatal(err)
	}
	if !resolved.NeedsSHA {
		t.Fatal("expected NeedsSHA")
	}
	if !strings.HasSuffix(root, "pack") && filepath.Base(root) != "pack" {
		t.Fatalf("unexpected root %s", root)
	}
	bin := "millennium"
	if runtime.GOOS == "windows" {
		bin = "millennium.exe"
	}
	if _, err := os.Stat(filepath.Join(root, "bin", bin)); err != nil {
		t.Fatal(err)
	}
}

func TestPrepareSourceMainRequiresAllow(t *testing.T) {
	// Ensure cwd is not a helpers tree so we hit the network path.
	// Prefer os.Chdir over t.Chdir so go vet stays happy with go 1.22 in go.mod.
	orig, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	tmp := t.TempDir()
	if err := os.Chdir(tmp); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(orig) })

	t.Setenv("MILLENNIUM_SOURCE_ROOT", "")
	var res Result
	_, _, _, _, err = prepareSource(Options{Track: "main"}, &res)
	if err == nil || !strings.Contains(err.Error(), "--allow-unsigned-main") {
		t.Fatalf("got %v", err)
	}
}
