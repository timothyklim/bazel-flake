{ pkgs, nixpkgs, lndir, src, version }:

with pkgs;
let
  sourceRoot = ".";
  arch = stdenv.hostPlatform.parsed.cpu.name;
  jdk = openjdk17_headless;
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
  # Script-based interpreters in shebangs aren't guaranteed to work,
  # especially on MacOS. So let's produce a binary
  bashWithDefaultShellUtils = stdenv.mkDerivation {
    name = "bash";
    src = bashWithDefaultShellUtilsSh;
    nativeBuildInputs = [ makeBinaryWrapper ];
    buildPhase = ''
      makeWrapper ${bashWithDefaultShellUtilsSh}/bin/bash $out/bin/bash
    '';
  };
  bazelFlags = [
    "--java_language_version=17"
    "--java_runtime_version=17"
    "--tool_java_language_version=17"
    "--tool_java_runtime_version=17"
    "--extra_toolchains=@local_jdk//:all"
  ];
  lockfile = src + "/MODULE.bazel.lock";
  distDir = callPackage "${nixpkgs}/pkgs/development/tools/build-managers/bazel/bazel_7/bazel-repository-cache.nix" { inherit lockfile; };
  remote_java_tools = stdenv.mkDerivation {
    inherit sourceRoot;

    name = "remote_java_tools_linux";
    src = distDir;

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ gcc-unwrapped ];

    buildPhase = ''
      FILENAME=$(ls ${distDir}|grep 'java_tools_linux.*zip'|head -n 1)
      ${unzip}/bin/unzip -q -d $out ./bazel-repository-cache/$FILENAME
    '';

    installPhase = ''
      chmod -R u+w $out
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

  buildInputs = [ jdk bashWithDefaultShellUtils ] ++ defaultShellUtils;
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

  bazel = bazel_7;
  bazelTargets = [ "//src:bazel_nojdk" ];
  bazelFetchFlags = [
    "--loading_phase_threads=HOST_CPUS"
  ];
  bazelFlags = bazelFlags ++ [
    "--enable_bzlmod"
    "--lockfile_mode=update"
  ] ++ lib.optional stdenv.isLinux "--override_repository=${remote_java_tools.name}=${remote_java_tools}";
  bazelBuildFlags = [
    "-c opt"
    "--extra_toolchains=@bazel_tools//tools/python:autodetecting_toolchain"
    # add version information to the build
    "--stamp"
    "--embed_label='${version}'"
  ];
  fetchConfigured = true;

  removeRulesCC = false;
  removeLocalConfigCc = true;
  removeLocal = false;

  dontAddBazelOpts = true;

  fetchAttrs = {
    inherit prePatch;

    postInstall = ''
      rm -rf $out

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

    # sha256 = lib.fakeSha256;
    sha256 = "sha256-xR7H5SRWZuuWOaxNSt8RaUFbJViq5FtQsWtK/1QO2D4=";
  };

  buildAttrs = {
    inherit prePatch;

    preConfigure = ''
      rm -rf $bazelOut/cache
      rm -f $bazelOut/MODULE.bazel.lock
      mkdir -p "$bazelUserRoot"
      tar xfz $deps --directory="$bazelUserRoot" cache/
      tar xfz $deps MODULE.bazel.lock
    '';

    patches = [
      "${nixpkgs}/pkgs/development/tools/build-managers/bazel/trim-last-argument-to-gcc-if-empty.patch"
      # ./patches/nixpkgs_python.patch

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
      function sedVerbose() {
        local path=$1; shift;
        sed -i".bak-nix" "$path" "$@"
        diff -U0 "$path.bak-nix" "$path" | sed "s/^/  /" || true
        rm -f "$path.bak-nix"
      }
    '' + ''
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

    installPhase = ''
      mkdir -p $out/bin
      mv bazel-bin/src/bazel_nojdk $out/bin/bazel
    '';

    doInstallCheck = false;
    installCheckPhase = ''
      export TEST_TMPDIR=$(pwd)

      hello_test () {
        $out/bin/bazel test \
          ${lib.concatStringsSep " " bazelFlags} \
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
