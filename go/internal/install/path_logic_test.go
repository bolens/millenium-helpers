package install

import "testing"

func TestPathWithDir(t *testing.T) {
	got, added := pathWithDir("", `C:\mh\bin`)
	if !added || got != `C:\mh\bin` {
		t.Fatalf("empty: got %q added=%v", got, added)
	}
	got, added = pathWithDir(`C:\Windows`, `C:\mh\bin`)
	if !added || got != `C:\Windows;C:\mh\bin` {
		t.Fatalf("append: got %q added=%v", got, added)
	}
	got, added = pathWithDir(`C:\Windows;`, `C:\mh\bin`)
	if !added || got != `C:\Windows;C:\mh\bin` {
		t.Fatalf("trailing semi: got %q added=%v", got, added)
	}
	got, added = pathWithDir(`C:\mh\bin;C:\Windows`, `C:\MH\bin`)
	if added || got != `C:\mh\bin;C:\Windows` {
		t.Fatalf("already present: got %q added=%v", got, added)
	}
}

func TestPathWithoutDir(t *testing.T) {
	got := pathWithoutDir(`C:\a;C:\mh\bin;C:\b`, `C:\MH\bin`)
	if got != `C:\a;C:\b` {
		t.Fatalf("got %q", got)
	}
	got = pathWithoutDir(`C:\mh\bin`, `C:\mh\bin`)
	if got != "" {
		t.Fatalf("got %q", got)
	}
}
