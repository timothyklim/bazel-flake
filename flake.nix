{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-22.11";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:timothyklim/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/7.0.0-pre.20230104.2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    let
      system = "x86_64-linux";
      sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
      pkgs = nixpkgs.legacyPackages.${system};
      jdk = java.packages.${system}.openjdk_19;
      bazel = import ./build.nix {
        inherit pkgs nixpkgs jdk src;
        version = sources.src.original.ref;
      };
      bazel-app = flake-utils.lib.mkApp { drv = bazel; };
      derivation = { inherit bazel; };
    in
    with pkgs; rec {
      packages.${system} = derivation // { default = bazel; };
      apps.${system}.bazel = bazel-app;
      defaultApp.${system} = bazel-app;
      legacyPackages.${system} = extend overlay;
      devShells.${system}.default = callPackage ./shell.nix {
        inherit src;
      };
      nixosModules.default = {
        nixpkgs.overlays = [ overlays.default ];
      };
      overlays.default = final: prev: derivation;
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
