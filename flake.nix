{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";

    src = {
      url = "github:bazelbuild/bazel/release-7.1.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, src }:
    with flake-utils.lib; eachSystem [ system.x86_64-linux system.aarch64-linux system.aarch64-darwin ] (system:
      let
        sources = (nixpkgs.lib.importJSON ./flake.lock).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = pkgs.jdk17_headless;
        bazel = pkgs.callPackage ./build.nix {
          inherit src;
          buildJdk = jdk;
          runJdk = jdk;
          version = sources.src.original.ref;
          rev = sources.src.locked.rev;
          # fixed-output derivation hash, set an empty string to compute a new one on update
          # deps-hash = pkgs.lib.fakeSha256;
          deps-hash = "sha256-P3Fdp3fJxfxXIyaSrF1DWfEF0RcqCZ43qXDHHMElb+w=";
        };
        bazel-app = flake-utils.lib.mkApp { drv = bazel; };
        derivation = { inherit bazel; };
      in
      rec {
        packages = derivation // { default = bazel; };
        apps.bazel = bazel-app;
        defaultApp = bazel-app;
        legacyPackages = pkgs.extend overlay;
        nixosModules.default = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
      });
}
