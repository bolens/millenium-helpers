package install

import (
	"strings"
	"testing"
)

func TestResolveTrackURLsOverride(t *testing.T) {
	t.Setenv("MILLENNIUM_HELPERS_RELEASE_URL", "https://example.test/helpers.tgz")
	t.Setenv("MILLENNIUM_HELPERS_RELEASE_SHA_URL", "")
	got, err := ResolveTrackURLs("release", "", "linux")
	if err != nil {
		t.Fatal(err)
	}
	if got.URL != "https://example.test/helpers.tgz" || !got.NeedsSHA {
		t.Fatalf("%+v", got)
	}
	if got.SHAURL != "https://example.test/helpers.tgz.sha256" {
		t.Fatalf("sha %q", got.SHAURL)
	}
}

func TestResolveTrackCheckout(t *testing.T) {
	t.Setenv("MILLENNIUM_HELPERS_RELEASE_URL", "")
	got, err := ResolveTrackURLs("checkout", "", "linux")
	if err != nil {
		t.Fatal(err)
	}
	if got.URL != "" || got.Track != "checkout" {
		t.Fatalf("%+v", got)
	}
}

func TestResolveTrackTagAsset(t *testing.T) {
	t.Setenv("MILLENNIUM_HELPERS_RELEASE_URL", "")
	got, err := ResolveTrackURLs("tag", "v2.7.0", "linux")
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != "2.7.0" || got.Ref != "v2.7.0" || !got.NeedsSHA {
		t.Fatalf("%+v", got)
	}
	if !strings.Contains(got.URL, "millennium-helpers-v2.7.0-") || !strings.Contains(got.URL, ".tar.gz") {
		t.Fatalf("url %q", got.URL)
	}
}
