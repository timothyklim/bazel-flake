{ pkgs, ... }:

with pkgs; mkShell {
  name = "bazel-env";

  buildInputs = [ python3 ];
}
