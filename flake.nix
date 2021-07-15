{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    src = {
      url = "github:bazelbuild/bazel";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, src }:
    let
      sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      bazel = import ./build.nix {
        inherit pkgs src;
        version = "5.0.0-pre";
      };
      bazel-app = flake-utils.lib.mkApp { drv = bazel; };
      derivation = { inherit bazel; };
    in
    with pkgs; rec {
      packages.${system} = derivation;
      defaultPackage.${system} = bazel;
      apps.${system}.bazel = bazel-app;
      defaultApp.${system} = bazel-app;
      legacyPackages.${system} = extend overlay;
      devShell.${system} = callPackage ./shell.nix {
        inherit bazel src;
      };
      nixosModule = {
        nixpkgs.overlays = [ overlay ];
      };
      overlay = final: prev: derivation;
    };
}
