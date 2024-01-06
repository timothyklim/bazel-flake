{ lib
, path
, stdenv
, buildBazelPackage
, writeTextFile
, writeShellApplication
, installShellFiles
, makeWrapper
, makeBinaryWrapper
, substituteAll
, bazel_7
, bash
, binutils-unwrapped
, coreutils
, diffutils
, file
, findutils
, gawk
, gnugrep
, gnupatch
, gnumake
, gnused
, gnutar
, gzip
, python3
, unzip
, which
, zip
  # Apple dependencies
, darwin
, libcxx
  # explicit arguments
, src
, version
, rev
, deps-hash
, buildJdk
, runJdk
  # see nixpkgs derivation
  # required to use bazel in `buildBazelPackage`.
, enableNixHacks ? false
}:

let
  bazel_path = "${path}/pkgs/development/tools/build-managers/bazel";

  inherit (darwin) cctools sigtool;
  inherit (darwin.apple_sdk_11_0.frameworks) CoreFoundation CoreServices Foundation IOKit;

  defaultShellUtils = [
    bash
    binutils-unwrapped
    coreutils
    diffutils
    file
    findutils
    gawk
    gnugrep
    gnupatch
    gnumake
    gnused
    gnutar
    gzip
    python3
    unzip
    which
    zip
  ];
  defaultShellPath = lib.makeBinPath defaultShellUtils;
  bashWithDefaultShellUtilsSh = writeShellApplication {
    name = "bash";
    runtimeInputs = defaultShellUtils;
    text = ''
      if [[ "$PATH" == "/no-such-path" ]]; then
        export PATH=${defaultShellPath}
      fi
      exec ${bash}/bin/bash "$@"
    '';
  };
  # see nixpkgs derivation
  bashWithDefaultShellUtils = stdenv.mkDerivation {
    name = "bash";
    src = bashWithDefaultShellUtilsSh;
    nativeBuildInputs = [ makeBinaryWrapper ];
    buildPhase = ''
      makeWrapper ${bashWithDefaultShellUtilsSh}/bin/bash $out/bin/bash
    '';
  };

  bazelFlags = [
    "--extra_toolchains=@bazel_tools//tools/jdk:all"
    "--tool_java_runtime_version=local_jdk"
    "--java_runtime_version=local_jdk"
  ];
  bazelRC = writeTextFile {
    name = "bazel-rc";
    text = ''
      startup --server_javabase=${runJdk.home}

      ${lib.concatStringsSep "\n" (map (flag: "build ${flag}") bazelFlags)}

      # load default location for the system wide configuration
      try-import /etc/bazel.bazelrc
    '';
  };
  prePatch = ''
    rm -f .bazelversion
  '';
in

buildBazelPackage {
  inherit src version;
  pname = "bazel";

  bazel = bazel_7;

  bazelTargets = [ "//src:bazel_nojdk" ];

  # we only need this to fetch deps needed to run tests in installCheckPhase
  bazelTestTargets = [
    "//examples/cpp:hello-success_test"
    "//examples/java-native/src/test/java/com/example/myproject:hello"
  ];

  dontAddBazelOpts = true;

  bazelFlags = bazelFlags ++ [
    "--enable_bzlmod"
    "--lockfile_mode=update"
  ];

  fetchConfigured = true;

  bazelFetchFlags = [
    "--loading_phase_threads=HOST_CPUS"
  ];

  fetchAttrs = {
    inherit prePatch;

    sha256 = deps-hash;

    buildInputs = [ buildJdk ];

    postInstall = ''
      rm $out
      # create the same archive but with cache and lockfile
      tar czf $out \
        --sort=name \
        --mtime='@1' \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        --directory="$bazelOut" external/ \
        --directory="$bazelUserRoot" cache/ \
        --directory="$PWD" MODULE.bazel.lock
    '';
  };

  bazelBuildFlags = [
    "-c opt"
    "--extra_toolchains=@bazel_tools//tools/python:autodetecting_toolchain"
    # add version information to the build
    "--stamp"
    "--embed_label='${version}- (@${lib.substring 0 7 rev})'"
  ];

  buildAttrs = {
    inherit prePatch;

    preConfigure = ''
      rm -rf $bazelOut/cache
      rm -f $bazelOut/MODULE.bazel.lock

      mkdir -p "$bazelUserRoot"
      tar xfz $deps --directory="$bazelUserRoot" cache/
      tar xfz $deps MODULE.bazel.lock
    '';

    # see nixpkgs derivation
    patches = [
      "${bazel_path}/bazel_7/java_toolchain.patch"
      "${bazel_path}/bazel_7/darwin_sleep.patch"
      "${bazel_path}/bazel_7/xcode_locator.patch"
      "${bazel_path}/trim-last-argument-to-gcc-if-empty.patch"

      (substituteAll {
        src = "${bazel_path}/strict_action_env.patch";
        strictActionEnvPatch = defaultShellPath;
      })
      (substituteAll {
        src = "${bazel_path}/bazel_rc.patch";
        bazelSystemBazelRCPath = bazelRC;
      })
    ] ++ lib.optional enableNixHacks "${bazel_path}/nix-hacks.patch";

    # see nixpkgs derivation
    postPatch =
      let
        # Workaround for https://github.com/NixOS/nixpkgs/issues/166205
        nixpkgs166205ldflag = lib.optionalString stdenv.cc.isClang "-l${stdenv.cc.libcxx.cxxabi.libName}";
        darwinPatches = ''
          bazelLinkFlags () {
            eval set -- "$NIX_LDFLAGS"
            local flag
            for flag in "$@"; do
              printf ' -Wl,%s' "$flag"
            done
          }

          # Explicitly configure gcov since we don't have it on Darwin, so autodetection fails
          export GCOV=${coreutils}/bin/false

          # Framework search paths aren't added by bintools hook
          # https://github.com/NixOS/nixpkgs/pull/41914
          export NIX_LDFLAGS+=" -F${CoreFoundation}/Library/Frameworks -F${CoreServices}/Library/Frameworks -F${Foundation}/Library/Frameworks -F${IOKit}/Library/Frameworks ${nixpkgs166205ldflag}"

          # libcxx includes aren't added by libcxx hook
          # https://github.com/NixOS/nixpkgs/pull/41589
          export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem ${lib.getDev libcxx}/include/c++/v1"
          # for CLang 16 compatibility in external/upb dependency
          export NIX_CFLAGS_COMPILE+=" -Wno-gnu-offsetof-extensions"

          # This variable is used by bazel to propagate env vars for homebrew,
          # which is exactly what we need too.
          export HOMEBREW_RUBY_PATH="foo"

          # don't use system installed Xcode to run clang, use Nix clang instead
          sed -i -E \
            -e "s;/usr/bin/xcrun (--sdk macosx )?clang;${stdenv.cc}/bin/clang $NIX_CFLAGS_COMPILE $(bazelLinkFlags) -framework CoreFoundation;g" \
            -e "s;/usr/bin/codesign;CODESIGN_ALLOCATE=${cctools}/bin/${cctools.targetPrefix}codesign_allocate ${sigtool}/bin/codesign;" \
            scripts/bootstrap/compile.sh \
            tools/osx/BUILD

          # nixpkgs's libSystem cannot use pthread headers directly, must import GCD headers instead
          sed -i -e "/#include <pthread\/spawn.h>/i #include <dispatch/dispatch.h>" src/main/cpp/blaze_util_darwin.cc

          # XXX: What do these do ?
          sed -i -e 's;"/usr/bin/libtool";_find_generic(repository_ctx, "libtool", "LIBTOOL", overriden_tools);g' tools/cpp/unix_cc_configure.bzl
          wrappers=( tools/cpp/osx_cc_wrapper.sh.tpl )
          for wrapper in "''${wrappers[@]}"; do
            sedVerbose $wrapper \
              -e "s,/usr/bin/xcrun install_name_tool,${cctools}/bin/install_name_tool,g"
          done
        '';

        genericPatches = ''
          # md5sum is part of coreutils
          sed -i 's|/sbin/md5|md5sum|g' src/BUILD third_party/ijar/test/testenv.sh

          echo
          echo "Substituting */bin/* hardcoded paths in src/main/java/com/google/devtools"
          # Prefilter the files with grep for speed
          grep -rlZ /bin/ \
            src/main/java/com/google/devtools \
            src/main/starlark/builtins_bzl/common/python \
            tools \
          | while IFS="" read -r -d "" path; do
            # If you add more replacements here, you must change the grep above!
            # Only files containing /bin are taken into account.
            sedVerbose "$path" \
              -e 's!/usr/local/bin/bash!${bashWithDefaultShellUtils}/bin/bash!g' \
              -e 's!/usr/bin/bash!${bashWithDefaultShellUtils}/bin/bash!g' \
              -e 's!/bin/bash!${bashWithDefaultShellUtils}/bin/bash!g' \
              -e 's!/usr/bin/env bash!${bashWithDefaultShellUtils}/bin/bash!g' \
              -e 's!/usr/bin/env python2!${python3}/bin/python!g' \
              -e 's!/usr/bin/env python!${python3}/bin/python!g' \
              -e 's!/usr/bin/env!${coreutils}/bin/env!g' \
              -e 's!/bin/true!${coreutils}/bin/true!g'
          done

          # append the PATH with defaultShellPath in tools/bash/runfiles/runfiles.bash
          echo "PATH=\$PATH:${defaultShellPath}" >> runfiles.bash.tmp
          cat tools/bash/runfiles/runfiles.bash >> runfiles.bash.tmp
          mv runfiles.bash.tmp tools/bash/runfiles/runfiles.bash

          patchShebangs . >/dev/null
        '';
      in
      ''
        function sedVerbose() {
          local path=$1; shift;
          sed -i".bak-nix" "$path" "$@"
          diff -U0 "$path.bak-nix" "$path" | sed "s/^/  /" || true
          rm -f "$path.bak-nix"
        }
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin darwinPatches
      + genericPatches;

    # see nixpkgs derivation
    __darwinAllowLocalNetworking = true;

    buildInputs = [ buildJdk bashWithDefaultShellUtils ] ++ defaultShellUtils;

    nativeBuildInputs = [
      installShellFiles
      makeWrapper
      python3
      unzip
      which
      zip
      python3.pkgs.absl-py # Needed to build fish completion
    ] ++ lib.optionals (stdenv.isDarwin) [
      cctools
      libcxx
      Foundation
      CoreFoundation
      CoreServices
    ];

    postBuild = ''
      echo "Generate bazel completions"
      mkdir -p completion
      ${bash}/bin/bash ./scripts/generate_bash_completion.sh \
          --bazel=bazel \
          --output=./completion/bazel-complete.bash \
          --prepend=./scripts/bazel-complete-header.bash \
          --prepend=./scripts/bazel-complete-template.bash
      ${python3}/bin/python3 ./scripts/generate_fish_completion.py \
          --bazel=bazel \
          --output=./completion/bazel-complete.fish
    '';

    installPhase = ''
      mkdir -p $out/bin
      mv bazel-bin/src/bazel_nojdk $out/bin/bazel

      installShellCompletion --bash \
        --name bazel.bash \
        ./completion/bazel-complete.bash
      installShellCompletion --zsh \
        --name _bazel \
        ./scripts/zsh_completion/_bazel
      installShellCompletion --fish \
        --name bazel.fish \
        ./completion/bazel-complete.fish
    '';

    # see nixpkgs derivation
    doInstallCheck = true;
    installCheckPhase = ''
      export TEST_TMPDIR=$(pwd)

      # we don't use scripts/packages/bazel.sh wrapper, which means we don't
      # need to test this as in nixpkgs derivation

      $out/bin/bazel \
        --batch \
        --output_base="$bazelOut" \
        --output_user_root="$bazelUserRoot" \
        test \
        --test_output=errors \
        examples/cpp:hello-success_test \
        examples/java-native/src/test/java/com/example/myproject:hello

      ## Test that the GSON serialisation files are present
      gson_classes=$(unzip -l $(bazel info install_base)/A-server.jar | grep GsonTypeAdapter.class | wc -l)
      if [ "$gson_classes" -lt 10 ]; then
        echo "Missing GsonTypeAdapter classes in A-server.jar. Lockfile generation will not work"
        exit 1
      fi

      runHook postInstall
    '';

    postFixup = ''
      mkdir -p $out/nix-support
      echo "${defaultShellPath}" >> $out/nix-support/depends
      echo "${bazelRC}" >> $out/nix-support/depends
    '' + lib.optionalString stdenv.isDarwin ''
      echo "${cctools}" >> $out/nix-support/depends
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
}
