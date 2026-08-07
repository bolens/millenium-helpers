package install

import "testing"

func TestWriteReadMeta(t *testing.T) {
	root := t.TempDir()
	if err := WriteMeta(root, Meta{Track: "checkout", Ref: "abc123", Version: "2.7.0"}); err != nil {
		t.Fatal(err)
	}
	m, ok, err := ReadMeta(root)
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if m.Track != "checkout" || m.Ref != "abc123" || m.Version != "2.7.0" || m.InstalledAt == "" {
		t.Fatalf("%+v", m)
	}
}
