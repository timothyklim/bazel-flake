build:
  nix build --system x86_64-linux -L .#bazelDeps .#bazelBootstrap .#bazel .#bazel_7
  nix build --system aarch64-darwin -L .#bazelDeps .#bazelBootstrap .#bazel .#bazel_7
