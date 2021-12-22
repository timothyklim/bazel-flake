{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.11";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:TawasalMessenger/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/6.0.0-pre.20211215.3";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (
      system:
      let
        sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = java.packages.${system}.jdk_17;
        bazel = import ./build.nix {
          inherit pkgs nixpkgs jdk src;
          version = sources.src.original.ref;
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
