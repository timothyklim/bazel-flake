{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux aarch64-darwin ]
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          jdk = pkgs.jdk21_headless;

          sources = with pkgs; {
            bazel = rec {
              version = "8.1.1";
              src = fetchurl {
                url = "https://github.com/bazelbuild/bazel/releases/download/${version}/bazel-${version}-dist.zip";
                hash = "sha256-TJSHoW94QRUAkvB9k6ZyfWbyxBM6YX1zncqOyD+wCZw=";
              };
            };

            bazelBootstrap = rec {
              version = "8.0.1";
              src = {
                x86_64-linux = fetchurl {
                  url = "https://github.com/bazelbuild/bazel/releases/download/${version}/bazel_nojdk-${version}-linux-x86_64";
                  hash = "sha256-KLejW8XcVQ3xD+kP9EGCRrODmHZwX7Sq3etdrVBNXHI=";
                };
                aarch64-darwin = fetchurl {
                  url = "https://github.com/bazelbuild/bazel/releases/download/${version}/bazel_nojdk-${version}-darwin-arm64";
                  hash = "sha256-7IKMKQ8+Qwi3ORzZgKSffdId1Zq13hKcshthWKYTtCA=";
                };
              };
            };
          };

          build = { dryRun }:
            with pkgs; with lib; darwin.apple_sdk_11_0.callPackage ./build.nix {
              inherit nixpkgs sources dryRun;
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
            inherit checker;
            inherit (bazel) bazelBootstrap bazelDeps bazelVendorDeps;

            bazel-dryRun = (build { dryRun = true; }).bazelDeps;
            default = bazel;
          };
          apps = {
            default = bazel-app;
            bazel = bazel-app;
          };
          legacyPackages = pkgs.extend overlays.default;
          devShells.default = with pkgs; mkShell {
            name = "bazel-env";
            buildInputs = [ just ];
          };
          overlays.default = final: prev: derivation;
          checks.hashes = pkgs.runCommand "hashes" { } ''
            mkdir -p $out

            echo 'bazel hash verified: ${sources.bazel.src}' > $out/success

            ${nixpkgs.lib.concatStringsSep "\n" (nixpkgs.lib.mapAttrsToList (platform: src:
              "echo '${platform} hash verified: ${src}' >> $out/success"
            ) sources.bazelBootstrap.src)}
          '';
          formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
        }) // {
      nixosModules.default = {
        nixpkgs.overlays = [ overlay ];
      };
      overlays.default = final: prev: {
        bazel = self.packages.${prev.system}.default;
      };
    };
}
