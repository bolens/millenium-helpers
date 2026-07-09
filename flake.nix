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
      in
      {
        packages.default = pkgs.callPackage ./nix/default.nix { };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            python3
            curl
            unzip
            git
            shellcheck
            ruff
          ];
        };
      }
    );
}
