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
        jdk = pkgs.jdk21_headless;
        build = { dryRun }:
          with pkgs; with lib; darwin.apple_sdk_11_0.callPackage ./build.nix {
            inherit nixpkgs dryRun;
            inherit (darwin) cctools sigtool;
            inherit (darwin.apple_sdk_11_0.frameworks) CoreFoundation CoreServices Foundation IOKit;

            buildJdk = jdk;
            runJdk = jdk;

            stdenv =
              if stdenv.isDarwin then darwin.apple_sdk.stdenv
              else if stdenv.cc.isClang then llvmPackages.stdenv
              else stdenv;
          };
        bazel = build { dryRun = false; };
        bazel-dryRun = (build { dryRun = true; }).bazelDeps;
        bazel-app = flake-utils.lib.mkApp { drv = bazel; };
        checker = with pkgs; stdenv.mkDerivation {
          name = "checker";
          nativeBuildInputs = [ makeWrapper ];
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out/bin
            cp ${./checker.sh} $out/bin/checker
            wrapProgram $out/bin/checker --prefix PATH : ${lib.makeBinPath [ gawk gnused ]}
          '';
        };
        derivation = { inherit bazel; };
      in
      rec {
        packages = derivation // {
          inherit bazel-dryRun checker;
          default = bazel;
        };
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
