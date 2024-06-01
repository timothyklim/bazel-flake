{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux aarch64-darwin ] (system:
      let
        sources = (nixpkgs.lib.importJSON ./flake.lock).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = pkgs.jdk17_headless;
        bazel = with pkgs; with lib; darwin.apple_sdk_11_0.callPackage ./build.nix {
          inherit nixpkgs;
          inherit (darwin) cctools sigtool;
          inherit (darwin.apple_sdk_11_0.frameworks) CoreFoundation CoreServices Foundation IOKit;

          buildJdk = jdk;
          runJdk = jdk;

          stdenv =
            if stdenv.isDarwin then darwin.apple_sdk.stdenv
            else if stdenv.cc.isClang then llvmPackages.stdenv
            else stdenv;
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
