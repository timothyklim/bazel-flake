{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-21.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:TawasalMessenger/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/6.0.0-pre.20220331.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, java, src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (
      system:
      let
        sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = java.packages.${system}.openjdk_18;
        bazel_5 = nixpkgs-unstable.legacyPackages.${system}.bazel_5;
        bazel = import ./build.nix {
          inherit pkgs nixpkgs jdk src;
          bazel_5 = bazel_5;
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
          # inherit bazel src;
          inherit src;
          bazel = bazel_5;
        };
        nixosModule = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
      }
    );
}
