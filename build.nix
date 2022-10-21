{ pkgs, nixpkgs, bazel_5, jdk, src, version }:

with pkgs;
let
  sourceRoot = ".";
  arch = stdenv.hostPlatform.parsed.cpu.name;
  defaultShellUtils = [
    bash
    binutils-unwrapped
    coreutils
    file
    findutils
    gawk
    gnugrep
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
        srcs."coverage_output_generator-v2.6.zip"
        srcs.build_bazel_rules_nodejs
        srcs."android_tools_pkg-0.27.0.tar.gz"
        srcs.bazel_toolchains
        srcs.com_github_grpc_grpc
        srcs.upb
        srcs.com_google_protobuf
        srcs.rules_pkg
        # srcs.rules_cc
        srcs."rules_cc-0.0.2.tar.gz"
        srcs.rules_java
        srcs.rules_proto
        srcs.com_google_absl
        srcs.com_googlesource_code_re2
        srcs.com_github_cares_cares
        srcs."java_tools-v11.8.zip"

        srcs."remote_java_tools_linux_for_testing"
        srcs."remotejdk11_linux"

        # Tests
        srcs.bazelci_rules
        srcs.rules_license
        srcs."2f9af297c84c55c8b871ba4495e01ade42476c92.tar.gz"
        srcs."4694024279bdac52b77e22dc87808bd0fd732b69.tar.gz"
        srcs."bazel-gazelle-v0.24.0.tar.gz"
        srcs."rules_nodejs-core-5.5.0.tar.gz"
      ]
    );
  jvm_flags = [
    "--java_language_version=11"
    "--java_runtime_version=11"
    "--tool_java_language_version=11"
    "--tool_java_runtime_version=11"
    "--extra_toolchains=@local_jdk//:all"
  ];

  distDir = runCommand "bazel-deps" { } ''
    mkdir -p $out
    for i in ${builtins.toString srcDeps}; do cp $i $out/$(stripHash $i); done
  '';
  remote_java_tools = stdenv.mkDerivation {
    inherit sourceRoot;

    name = "remote_java_tools_linux";

    src = srcDepsSet."remote_java_tools_linux_for_testing";

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

      # load default location for the system wide configuration
      try-import /etc/bazel.bazelrc
    '';
  };
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
  ];

  bazel = bazel_5;
  bazelTarget = "//src:bazel";
  bazelFetchFlags = [
    "--loading_phase_threads=HOST_CPUS"
  ];
  bazelFlags = jvm_flags ++ [
    "-c opt"
    "--override_repository=${remote_java_tools.name}=${remote_java_tools}"
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

    # sha256 = lib.fakeSha256;
    sha256 = "sha256-EZ6Gjyi1DlJhPyvzyTaABRl2XP7od39EpjKkX3IZ1/o=";
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
    '';

    installPhase = ''
      mkdir -p $out/bin
      mv bazel-bin/src/bazel $out/bin/bazel
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      export TEST_TMPDIR=$(pwd)

      hello_test () {
        $out/bin/bazel test \
          ${lib.concatStringsSep " " jvm_flags} \
          --test_output=errors \
          examples/cpp:hello-success_test \
          examples/java-native/src/test/java/com/example/myproject:hello
      }

      # test whether $WORKSPACE_ROOT/tools/bazel works

      mkdir -p tools
      cat > tools/bazel <<"EOF"
      #!${runtimeShell} -e
      exit 1
      EOF
      chmod +x tools/bazel

      # first call should fail if tools/bazel is used
      ! hello_test

      cat > tools/bazel <<"EOF"
      #!${runtimeShell} -e
      exec "$BAZEL_REAL" "$@"
      EOF

      # second call succeeds because it defers to $out/bin/bazel-{version}-{os_arch}
      hello_test
    '';

    # Save paths to hardcoded dependencies so Nix can detect them.
    postFixup = ''
      mkdir -p $out/nix-support
      echo "${bash} ${defaultShellPath}" >> $out/nix-support/depends
      echo "${python3}" >> $out/nix-support/depends
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
}
