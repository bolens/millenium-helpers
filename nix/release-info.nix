# Pinned release metadata for Nix packages.
# Updated by scripts/ci/update-packaging-versions.sh on each release.
{
  version = "3.0.0";
  # SRI hash of millennium-helpers-v*-linux-amd64.tar.gz (release asset / -bin)
  srcAssetHash = "sha256-3noNeuiW3qJumCxFWFshFwFeciS5D3VKWid0V40dPZI=";
  # Legacy alias used by older flakes
  srcHash = "sha256-3noNeuiW3qJumCxFWFshFwFeciS5D3VKWid0V40dPZI=";
  # SRI hash of millennium-helpers-v*-src.tar.gz (from-source packages)
  srcGitHash = "sha256-OjMkYebprHrDBFe5K1Zx0eQsY8emG+nV5Fv4R7MWV9g=";
}
