{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";

    src = {
      url = "github:bazelbuild/bazel/7.0.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, src }:
    with flake-utils.lib; eachSystem [ system.x86_64-linux system.aarch64-linux system.aarch64-darwin ] (system:
      let
        sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        bazel = pkgs.callPackage ./build.nix {
          inherit pkgs nixpkgs src;
          version = sources.src.original.ref;
        };
        bazel-app = flake-utils.lib.mkApp { drv = bazel; };
        derivation = { inherit bazel; };
      in
      with pkgs; rec {
        packages = derivation // { default = bazel; };
        apps.bazel = bazel-app;
        defaultApp = bazel-app;
        legacyPackages = extend overlay;
        devShell = callPackage ./shell.nix { };
        nixosModules.default = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
      });
}
