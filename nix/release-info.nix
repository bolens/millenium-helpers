# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.2.1";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-KBndrZQyOEIee/+xWFlQtv4yL8iOh00ZpGBJZUBmHS8=";
  # Legacy alias used by older flakes
  srcHash = "sha256-KBndrZQyOEIee/+xWFlQtv4yL8iOh00ZpGBJZUBmHS8=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-e0drzu7Q4cPv21L3tUcz8tc+L4JlICypiRjCMe6f9gY=";
}
