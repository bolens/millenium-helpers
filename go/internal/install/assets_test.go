package install

import "testing"

func TestAssetNames(t *testing.T) {
	if got := AssetHelpers("2.7.0", "linux", "amd64", "tar.gz"); got != "millennium-helpers-v2.7.0-linux-amd64.tar.gz" {
		t.Fatal(got)
	}
	if got := AssetHelpers("v2.7.0", "windows", "amd64", "zip"); got != "millennium-helpers-v2.7.0-windows-amd64.zip" {
		t.Fatal(got)
	}
	if got := AssetSrc("2.7.0", "tar.gz"); got != "millennium-helpers-v2.7.0-src.tar.gz" {
		t.Fatal(got)
	}
	if got := AssetGo("2.7.0", "linux", "amd64"); got != "millennium-v2.7.0-linux-amd64" {
		t.Fatal(got)
	}
	if got := AssetGo("2.7.0", "windows", "amd64"); got != "millennium-v2.7.0-windows-amd64.exe" {
		t.Fatal(got)
	}
	tag, err := NormalizeTag("2.7.0")
	if err != nil || tag != "v2.7.0" {
		t.Fatalf("%s %v", tag, err)
	}
}

func TestValidateTrack(t *testing.T) {
	tr, tag, err := ValidateTrack("release", "")
	if err != nil || tr != "release" {
		t.Fatalf("%s %s %v", tr, tag, err)
	}
	tr, tag, err = ValidateTrack("release", "2.7.0")
	if err != nil || tr != "tag" || tag != "v2.7.0" {
		t.Fatalf("%s %s %v", tr, tag, err)
	}
	if _, _, err := ValidateTrack("nightly", ""); err == nil {
		t.Fatal("expected invalid track")
	}
}
