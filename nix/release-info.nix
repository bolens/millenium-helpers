# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.1.0";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-qw264wm251AiG+7otLBWFrxTVHGzJoUw+5C3oXT+myU=";
  # Legacy alias used by older flakes
  srcHash = "sha256-qw264wm251AiG+7otLBWFrxTVHGzJoUw+5C3oXT+myU=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-vFjfh2KcISowV5QHAwW7YYi3jHqqALg1sSIzoEyTcPw=";
}
