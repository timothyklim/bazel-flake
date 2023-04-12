{ pkgs, src, }:

with pkgs;
let
  updater = writeScript "update-bazel-deps.sh" ''
    #!${runtimeShell}
    checkout=$(mktemp -d)
    cp -r ${src}/* $checkout && \
    cd $checkout && \
    rm -f .bazelversion && \
    BAZEL_USE_CPP_ONLY_TOOLCHAIN=1 \
      ${bazel_4}/bin/bazel \
        query 'kind(http_archive, //external:all) + kind(http_file, //external:all) + kind(distdir_tar, //external:all) + kind(git_repository, //external:all)' \
        --loading_phase_threads=1 \
        --output build \
    | ${python3}/bin/python3 ${./update-srcDeps.py}
  '';
in
mkShell {
  name = "bazel-env";

  buildInputs = [ python3 ];

  shellHook = ''
    ${updater} > ./src-deps.json
  '';
}
