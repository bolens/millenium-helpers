# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.1.0";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-vS3EpUTD8/Uxs60Ev0v0h/8SFT7vjbrC+ZtrSsQC+p0=";
  # Legacy alias used by older flakes
  srcHash = "sha256-vS3EpUTD8/Uxs60Ev0v0h/8SFT7vjbrC+ZtrSsQC+p0=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-Wr5jPCCeX0VjpDq076uv6KEg8by9Oo/004XPcmmYcuE=";
}
