{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-22.11";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:timothyklim/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/7.0.0-pre.20230412.2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    with flake-utils.lib; eachSystem [ system.x86_64-linux system.aarch64-linux system.aarch64-darwin ] (system:
      let
        sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = java.packages.${system}.openjdk_20;
        bazel = import ./build.nix {
          inherit pkgs nixpkgs jdk src;
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
        devShell = callPackage ./shell.nix { inherit src; };
        nixosModules.default = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
      });
}
