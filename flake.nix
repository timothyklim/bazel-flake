{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/fc8a946321c9ade8134f9b4ac9d12ed23a0ec698";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:TawasalMessenger/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (
      system:
      let
        sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk =
          if pkgs.stdenv.isLinux
          then java.packages.${system}.openjdk_17
          else pkgs.adoptopenjdk-jre-hotspot-bin-17;
        bazel = import ./build.nix {
          inherit pkgs nixpkgs jdk src;
          version = "5.0.0-pre"; # sources.src.original.ref;
        };
        bazel-app = flake-utils.lib.mkApp { drv = bazel; };
        derivation = { inherit bazel; };
      in
      with pkgs; rec {
        packages = derivation;
        defaultPackage = bazel;
        apps.bazel = bazel-app;
        defaultApp = bazel-app;
        legacyPackages = extend overlay;
        devShell = callPackage ./shell.nix {
          inherit bazel src;
        };
        nixosModule = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
      }
    );
}
