{ pkgs, src, }:

with pkgs;
let
  java_tools-patch = fetchpatch {
    url = "https://patch-diff.githubusercontent.com/raw/bazelbuild/bazel/pull/18902.patch";
    sha256 = "sha256-pBEyOCyzF92TJhA/FC4alWV7IX4WPqR5vFfC1nqvtsU=";
  };
  updater = writeScript "update-bazel-deps.sh" ''
    #!${runtimeShell}
    checkout=$(mktemp -d)
    cp -r ${src}/* $checkout && \
    chmod -R u+w $checkout && \
    cd $checkout && \
    rm -f .bazelversion && \
    patch -p1 < ${java_tools-patch} > /dev/null 2>&1 && \
    BAZEL_USE_CPP_ONLY_TOOLCHAIN=1 \
      ${bazel_6}/bin/bazel \
        query 'kind(http_archive, //external:*) + kind(http_file, //external:*) + kind(distdir_tar, //external:*) + kind(git_repository, //external:*)' \
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
