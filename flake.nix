{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";

    src = {
      url = "github:bazelbuild/bazel/release-7.2.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, src }:
    with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin ] (system:
      let
        sources = (nixpkgs.lib.importJSON ./flake.lock).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = pkgs.jdk21_headless;
        bazel = with pkgs; with lib; callPackage ./build.nix {
          inherit src;
          buildJdk = jdk;
          runJdk = jdk;
          version =
            let
              xs = splitString "/" sources.src.original.ref;
              ys = splitString "-" (elemAt xs (length (xs) - 1));
            in
            elemAt ys (length (ys) - 1);
          rev = sources.src.locked.rev;
          # fixed-output derivation hash, set an empty string to compute a new one on update
          # deps-hash = pkgs.lib.fakeSha256;
          deps-hash =
            if stdenv.isDarwin then
              if stdenv.hostPlatform.isAarch then "sha256-XXjcrP6DgKtNRnsohTAayFYa20LB48nP/AEoBO4OKpo="
              else "sha256-TL+BxKgPzWs7Kc0zDy3nlpOusbNYBG6CJgF+FUPqvKg="
            else "sha256-laC/9ykJ+YLSTUtOK1ETOmLDMYiTw1nwP0UY+Ws0a/o=";
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
