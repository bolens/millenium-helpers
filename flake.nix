{
  description = "Utility scripts for managing, repairing, upgrading, rolling back, viewing logs, managing themes, and scheduling updates for Millennium on Linux";

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
