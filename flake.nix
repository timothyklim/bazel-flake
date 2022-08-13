{
  description = "Bazel flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.05";
    flake-utils.url = "github:numtide/flake-utils";

    java.url = "github:TawasalMessenger/jdk-flake";
    src = {
      url = "github:bazelbuild/bazel/6.0.0-pre.20220804.3";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, java, src }:
    let
      system = "x86_64-linux";
      sources = with builtins; (fromJSON (readFile ./flake.lock)).nodes;
      pkgs = nixpkgs.legacyPackages.${system};
      jdk = java.packages.${system}.openjdk_19;
      bazel_5 = pkgs.bazel_5;
      bazel = import ./build.nix {
        inherit pkgs nixpkgs bazel_5 jdk src;
        version = sources.src.original.ref;
      };
      bazel-app = flake-utils.lib.mkApp { drv = bazel; };
      derivation = { inherit bazel; };
    in
    with pkgs; rec {
      packages.${system} = derivation;
      defaultPackage.${system} = bazel;
      apps.bazel.${system} = bazel-app;
      defaultApp.${system} = bazel-app;
      legacyPackages.${system} = extend overlay;
      devShell.${system} = callPackage ./shell.nix {
        # inherit bazel src;
        inherit src;
        bazel = bazel_5;
      };
      nixosModule = {
        nixpkgs.overlays = [ overlay ];
      };
      overlay = final: prev: derivation;
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
