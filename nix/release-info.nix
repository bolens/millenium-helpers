# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "2.6.2";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-wHfD9TbnUed2+rsylgCxjXRS1FWi4t0ZCEkTMlafTlU=";
  # Legacy alias used by older flakes
  srcHash = "sha256-wHfD9TbnUed2+rsylgCxjXRS1FWi4t0ZCEkTMlafTlU=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-ZeTHY4T3n151g4gJowNp6N1RUNfGG8trCT0FVErS5Bk=";
}
