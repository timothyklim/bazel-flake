{ pkgs, nixpkgs, jdk, src, version }:

with pkgs;
let
  sourceRoot = ".";
  system = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  arch = stdenv.hostPlatform.parsed.cpu.name;
  defaultShellUtils = [ bash coreutils findutils gawk gnugrep gnutar gnused gzip which unzip file zip python3 ];
  defaultShellPath = lib.makeBinPath defaultShellUtils;
  srcDeps = lib.attrsets.attrValues srcDepsSet;
  srcDepsSet =
    let
      srcs = (builtins.fromJSON (builtins.readFile ./src-deps.json));
      toFetchurl = d: lib.attrsets.nameValuePair d.name (
        fetchurl {
          urls = d.urls;
          sha256 = d.sha256;
        }
      );
    in
    builtins.listToAttrs (
      map toFetchurl [
        srcs.desugar_jdk_libs
        srcs.io_bazel_skydoc
        srcs.bazel_skylib
        srcs.io_bazel_rules_sass
        srcs.platforms
        srcs."coverage_output_generator-v2.5.zip"
        srcs.build_bazel_rules_nodejs
        srcs."android_tools_pkg-0.23.0.tar.gz"
        srcs.bazel_toolchains
        srcs.com_github_grpc_grpc
        srcs.upb
        srcs.com_google_protobuf
        srcs.rules_pkg
        srcs.rules_cc
        srcs.rules_java
        srcs.rules_proto
        srcs.com_google_absl
        srcs.com_googlesource_code_re2
        srcs.com_github_cares_cares
        srcs."java_tools-v11.6.zip"

        srcs."remote_java_tools_${system}_for_testing"
        srcs."remotejdk11_${if stdenv.hostPlatform.isDarwin then "macos" else "linux"}"
      ]
    );

  distDir = runCommand "bazel-deps" { } ''
    mkdir -p $out
    for i in ${builtins.toString srcDeps}; do cp $i $out/$(stripHash $i); done
  '';
  remote_java_tools = stdenv.mkDerivation {
    inherit sourceRoot;

    name = "remote_java_tools_${system}";

    src = srcDepsSet."remote_java_tools_${system}_for_testing";

    nativeBuildInputs = [ autoPatchelfHook unzip ];
    buildInputs = [ gcc-unwrapped ];

    buildPhase = ''
      mkdir $out;
    '';

    installPhase = ''
      cp -Ra * $out/
      touch $out/WORKSPACE
    '';
  };
  bazelRC = writeTextFile {
    name = "bazel-rc";
    text = ''
      startup --server_javabase=${jdk.home}

      build --distdir=${distDir}
      fetch --distdir=${distDir}
      query --distdir=${distDir}

      build --override_repository=${remote_java_tools.name}=${remote_java_tools}
      fetch --override_repository=${remote_java_tools.name}=${remote_java_tools}
      query --override_repository=${remote_java_tools.name}=${remote_java_tools}

      # Provide a default java toolchain, this will be the same as ${jdk.home}
      build --host_javabase='@local_jdk//:jdk'

      # load default location for the system wide configuration
      try-import /etc/bazel.bazelrc
    '';
  };
  darwinPatches = with darwin; with apple_sdk.frameworks; ''
    bazelLinkFlags () {
      eval set -- "$NIX_LDFLAGS"
      local flag
      for flag in "$@"; do
        printf ' -Wl,%s' "$flag"
      done
    }

    # Disable Bazel's Xcode toolchain detection which would configure compilers
    # and linkers from Xcode instead of from PATH
    export BAZEL_USE_CPP_ONLY_TOOLCHAIN=1

    # Explicitly configure gcov since we don't have it on Darwin, so autodetection fails
    export GCOV=${coreutils}/bin/false

    # Framework search paths aren't added by bintools hook
    # https://github.com/NixOS/nixpkgs/pull/41914
    export NIX_LDFLAGS+=" -F${CoreFoundation}/Library/Frameworks -F${CoreServices}/Library/Frameworks -F${Foundation}/Library/Frameworks"

    # libcxx includes aren't added by libcxx hook
    # https://github.com/NixOS/nixpkgs/pull/41589
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem ${lib.getDev libcxx}/include/c++/v1"

    # don't use system installed Xcode to run clang, use Nix clang instead
    sed -i -E "s;/usr/bin/xcrun (--sdk macosx )?clang;${stdenv.cc}/bin/clang $NIX_CFLAGS_COMPILE $(bazelLinkFlags) -framework CoreFoundation;g" \
      scripts/bootstrap/compile.sh \
      tools/osx/BUILD

    substituteInPlace scripts/bootstrap/compile.sh --replace ' -mmacosx-version-min=10.9' ""

    # nixpkgs's libSystem cannot use pthread headers directly, must import GCD headers instead
    sed -i -e "/#include <pthread\/spawn.h>/i #include <dispatch/dispatch.h>" src/main/cpp/blaze_util_darwin.cc

    # clang installed from Xcode has a compatibility wrapper that forwards
    # invocations of gcc to clang, but vanilla clang doesn't
    sed -i -e 's;_find_generic(repository_ctx, "gcc", "CC", overriden_tools);_find_generic(repository_ctx, "clang", "CC", overriden_tools);g' tools/cpp/unix_cc_configure.bzl

    sed -i -e 's;/usr/bin/libtool;${cctools}/bin/libtool;g' tools/cpp/unix_cc_configure.bzl
    wrappers=( tools/cpp/osx_cc_wrapper.sh tools/cpp/osx_cc_wrapper.sh.tpl )
    for wrapper in "''${wrappers[@]}"; do
      sed -i -e "s,/usr/bin/install_name_tool,${cctools}/bin/install_name_tool,g" $wrapper
    done
  '';
in
buildBazelPackage {
  inherit src version;
  pname = "bazel";

  buildInputs = [ python3 jdk11_headless ];
  nativeBuildInputs = [
    bash
    coreutils
    installShellFiles
    makeWrapper
    python3
    unzip
    which
    zip
  ] ++ lib.optionals (stdenv.isDarwin) (with darwin; with apple_sdk.frameworks; [ cctools libcxx CoreFoundation CoreServices Foundation Libsystem ]);

  bazel = bazel_5;
  bazelTarget = "//src:bazel";
  bazelFetchFlags = [
    "--loading_phase_threads=HOST_CPUS"
  ];
  bazelFlags = [
    "-c opt"
    "--override_repository=${remote_java_tools.name}=${remote_java_tools}"
    "--java_language_version=11"
    "--java_runtime_version=11"
    "--tool_java_language_version=11"
    "--tool_java_runtime_version=11"
    "--extra_toolchains=@local_jdk//:all"
  ];
  fetchConfigured = true;

  removeRulesCC = false;
  removeLocalConfigCc = true;
  removeLocal = false;

  dontAddBazelOpts = true;

  fetchAttrs = {
    postInstall = ''
      nix_build_top=$(echo $NIX_BUILD_TOP|sed "s/\/\//\//g")
      find $bazelOut/external -type l | while read symlink; do
        new_target="$(readlink "$symlink" | sed "s,$nix_build_top,NIX_BUILD_TOP,")"
        rm "$symlink"
        ln -sf "$new_target" "$symlink"
      done
    '';

    # lib.fakeSha256
    sha256 =
      if stdenv.hostPlatform.isDarwin
      then lib.fakeSha256
      else "wapVXLsXpDuN1B61UXyAYiidQxJC4/ntlUYvdVPMTaI=";
  };

  buildAttrs = {
    patches = [
      "${nixpkgs}/pkgs/development/tools/build-managers/bazel/trim-last-argument-to-gcc-if-empty.patch"

      (substituteAll {
        src = ./patches/actions_path.patch;
        actionsPathPatch = defaultShellPath;
      })
      (substituteAll {
        src = ./patches/strict_action_env.patch;
        strictActionEnvPatch = defaultShellPath;
      })
      (substituteAll {
        src = ./patches/bazel_rc.patch;
        bazelSystemBazelRCPath = bazelRC;
      })

      ./patches/default_java_toolchain.patch
      ./patches/no-arc.patch
    ];

    postPatch = ''
      # md5sum is part of coreutils
      sed -i 's|/sbin/md5|md5sum|' src/BUILD

      # replace initial value of pythonShebang variable in BazelPythonSemantics.java
      substituteInPlace src/main/java/com/google/devtools/build/lib/bazel/rules/python/BazelPythonSemantics.java \
        --replace '"#!/usr/bin/env " + pythonExecutableName' "\"#!${python3}/bin/python\""

      # substituteInPlace is rather slow, so prefilter the files with grep
      grep -rlZ /bin src/main/java/com/google/devtools | while IFS="" read -r -d "" path; do
        # If you add more replacements here, you must change the grep above!
        # Only files containing /bin are taken into account.
        # We default to python3 where possible. See also `postFixup` where
        # python3 is added to $out/nix-support
        substituteInPlace "$path" \
          --replace /bin/bash ${bash}/bin/bash \
          --replace "/usr/bin/env bash" ${bash}/bin/bash \
          --replace "/usr/bin/env python" ${python3}/bin/python \
          --replace /usr/bin/env ${coreutils}/bin/env \
          --replace /bin/true ${coreutils}/bin/true
      done

      # bazel test runner include references to /bin/bash
      substituteInPlace tools/build_rules/test_rules.bzl --replace /bin/bash ${bash}/bin/bash

      for i in $(find tools/cpp/ -type f)
      do
        substituteInPlace $i --replace /bin/bash ${bash}/bin/bash
      done

      # Fixup scripts that generate scripts. Not fixed up by patchShebangs below.
      substituteInPlace scripts/bootstrap/compile.sh --replace /bin/bash ${bash}/bin/bash

      # append the PATH with defaultShellPath in tools/bash/runfiles/runfiles.bash
      echo "PATH=\$PATH:${defaultShellPath}" >> runfiles.bash.tmp
      cat tools/bash/runfiles/runfiles.bash >> runfiles.bash.tmp
      mv runfiles.bash.tmp tools/bash/runfiles/runfiles.bash

      patchShebangs .
    '' + lib.optionalString stdenv.hostPlatform.isDarwin darwinPatches;

    installPhase = ''
      mkdir -p $out/bin
      mv bazel-bin/src/bazel $out/bin/bazel
    '';

    # doInstallCheck = true;
    # installCheckPhase = ''
    #   export TEST_TMPDIR=$(pwd)

    #   hello_test () {
    #     $out/bin/bazel test \
    #       --test_output=errors \
    #       examples/cpp:hello-success_test \
    #       examples/java-native/src/test/java/com/example/myproject:hello
    #   }

    #   # test whether $WORKSPACE_ROOT/tools/bazel works

    #   mkdir -p tools
    #   cat > tools/bazel <<"EOF"
    #   #!${runtimeShell} -e
    #   exit 1
    #   EOF
    #   chmod +x tools/bazel

    #   # first call should fail if tools/bazel is used
    #   ! hello_test

    #   cat > tools/bazel <<"EOF"
    #   #!${runtimeShell} -e
    #   exec "$BAZEL_REAL" "$@"
    #   EOF

    #   # second call succeeds because it defers to $out/bin/bazel-{version}-{os_arch}
    #   hello_test
    # '';

    # Save paths to hardcoded dependencies so Nix can detect them.
    postFixup = ''
      mkdir -p $out/nix-support
      echo "${bash} ${defaultShellPath}" >> $out/nix-support/depends
      echo "${python3}" >> $out/nix-support/depends
    '' + lib.optionalString stdenv.isDarwin ''
      echo "${darwin.cctools}" >> $out/nix-support/depends
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
}
