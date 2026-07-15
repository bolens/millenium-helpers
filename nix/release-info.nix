# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.0.0";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-lrqpKFvhkaE2qrRguk517cQmhCMzt9+PcZyN5yRzDKE=";
  # Legacy alias used by older flakes
  srcHash = "sha256-lrqpKFvhkaE2qrRguk517cQmhCMzt9+PcZyN5yRzDKE=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-USZvhnoifRxxIrkiH6dsXZJtloaSQ0lIRna923U1GC0=";
}
