{
  description = "Cross-platform utility scripts and Model Context Protocol (MCP) server for managing, upgrading, diagnosing, and controlling Millennium on Linux";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        releaseInfo = import ./nix/release-info.nix;

        # From-source tagged release (default): build Go from controlled -src.tar.gz.
        millennium-helpers = pkgs.callPackage ./nix/default.nix {
          version = releaseInfo.version;
          src = pkgs.fetchurl {
            url = "https://github.com/bolens/millenium-helpers/releases/download/v${releaseInfo.version}/millennium-helpers-v${releaseInfo.version}-src.tar.gz";
            hash = releaseInfo.srcGitHash;
          };
          buildGoDispatcher = true;
        };

        # Prebuilt release assets (scripts tarball; Go binary when embedded).
        millennium-helpers-bin = pkgs.callPackage ./nix/default.nix {
          pname = "millennium-helpers-bin";
          version = releaseInfo.version;
          src = pkgs.fetchurl {
            url = "https://github.com/bolens/millenium-helpers/releases/download/v${releaseInfo.version}/millennium-helpers-v${releaseInfo.version}-linux-amd64.tar.gz";
            hash = releaseInfo.srcAssetHash or releaseInfo.srcHash;
          };
          unpackFlat = true;
          buildGoDispatcher = false;
        };

        millennium-helpers-git = pkgs.callPackage ./nix/default.nix {
          pname = "millennium-helpers-git";
          version =
            if self ? shortRev then "unstable-${self.shortRev}"
            else if self ? dirtyShortRev then "unstable-${self.dirtyShortRev}"
            else "unstable-dirty";
          src = pkgs.lib.cleanSource ./.;
          buildGoDispatcher = true;
        };
      in
      {
        packages = {
          inherit millennium-helpers millennium-helpers-bin millennium-helpers-git;
          default = millennium-helpers;
        };

        apps = {
          default = {
            type = "app";
            program = "${millennium-helpers}/bin/millennium";
          };
          millennium-helpers-bin = {
            type = "app";
            program = "${millennium-helpers-bin}/bin/millennium";
          };
          millennium-helpers-git = {
            type = "app";
            program = "${millennium-helpers-git}/bin/millennium";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            python3
            python3Packages.pyyaml
            curl
            unzip
            git
            shellcheck
            ruff
            go
            gnumake
          ];
        };
      }
    );
}
