# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.0.1";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-XsPEKcFvQJbLD7ZqVhuf2PROio/Q1OTefMbsmlilPww=";
  # Legacy alias used by older flakes
  srcHash = "sha256-XsPEKcFvQJbLD7ZqVhuf2PROio/Q1OTefMbsmlilPww=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-TZNB0YRRYvSeha76xIKJUnYjCOo6PBDLn/+RJaERPx8=";
}
