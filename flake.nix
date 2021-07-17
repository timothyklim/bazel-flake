{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:TawasalMessenger/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/5.0.0-pre.20210708.4";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    let
      sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      openjdk_16 = java.packages.${system}.openjdk_16;
      bazel = import ./build.nix {
        inherit pkgs src;
        runJdk = openjdk_16.home;
        version = "5.0.0-pre.20210708.4";
      };
      bazel-app = flake-utils.lib.mkApp { drv = bazel; };
      derivation = { inherit bazel; };
    in
    with pkgs; rec {
      packages.${system} = derivation;
      defaultPackage.${system} = bazel;
      apps.${system}.bazel = bazel-app;
      defaultApp.${system} = bazel-app;
      legacyPackages.${system} = extend overlay;
      devShell.${system} = callPackage ./shell.nix {
        inherit bazel src;
      };
      nixosModule = {
        nixpkgs.overlays = [ overlay ];
      };
      overlay = final: prev: derivation;
    };
}
