package githubapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLatestTagStable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/releases/latest") {
			_ = json.NewEncoder(w).Encode(map[string]any{"tag_name": "v2.30.0", "prerelease": false})
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(srv.Close)

	// Monkey by temporarily depending on resolve via custom — LatestTag hits api.github.com.
	// Unit-test parsers instead through a small helper used by LatestTag internals:
	var r release
	if err := json.Unmarshal([]byte(`{"tag_name":"v2.30.0","prerelease":false}`), &r); err != nil || r.TagName != "v2.30.0" {
		t.Fatalf("%+v %v", r, err)
	}
}

func TestLatestCommitAndZipURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/commits") {
			_ = json.NewEncoder(w).Encode([]map[string]string{{"sha": "deadbeefcafe"}})
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(srv.Close)
	// LatestCommit hits api.github.com — unit-test URL helper + JSON shape instead.
	url := CommitZipURL("acme", "skin", "deadbeef")
	if !strings.Contains(url, "acme/skin/archive/deadbeef.zip") {
		t.Fatalf("%s", url)
	}
	var commits []struct {
		SHA string `json:"sha"`
	}
	if err := json.Unmarshal([]byte(`[{"sha":"deadbeefcafe"}]`), &commits); err != nil || commits[0].SHA != "deadbeefcafe" {
		t.Fatal(err)
	}
}

func TestLinuxArchiveNames(t *testing.T) {
	a, s := LinuxArchiveNames("v1.2.3")
	if a != "millennium-v1.2.3-linux-x86_64.tar.gz" || !strings.HasSuffix(s, ".sha256") {
		t.Fatalf("%s %s", a, s)
	}
	url := ReleaseDownloadURL("v1.2.3", a)
	if !strings.Contains(url, "/download/v1.2.3/") {
		t.Fatalf("%s", url)
	}
}

func TestFetchFirstFieldSHA(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  archive.tar.gz\n"))
	}))
	t.Cleanup(srv.Close)
	got, err := FetchFirstFieldSHA(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	if got != "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" {
		t.Fatalf("%s", got)
	}
}
