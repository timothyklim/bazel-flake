build:
  nix build --system x86_64-linux -L .#bazelDeps .#bazelBootstrap .#bazel
  nix build --system aarch64-darwin -L .#bazelDeps .#bazelBootstrap .#bazel
