//go:build linux

package upgrade

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestPasswdHomesFiltersSystemAccounts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passwd")
	body := "root:x:0:0:root:/root:/bin/bash\n" +
		"alice:x:1000:1000::/home/alice:/bin/bash\n" +
		"service:x:1001:1001::/srv/service:/usr/sbin/nologin\n" +
		"bob:x:1002:1002::/home/bob:/bin/zsh\n" +
		"nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin\n"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := passwdHomes(path)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"/home/alice", "/home/bob"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}
