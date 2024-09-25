#!/usr/bin/env bash

set -exo

run() {
    tempdir=$(mktemp -d)
    hash=$(nix build -L $(pwd)#bazel-dryRun 2>&1 | tee /dev/stderr | awk '/got:/{print $2}')

    cp -r $(pwd)/* $tempdir
    sed -i "s|sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=|$hash|g" $tempdir/build.nix
    echo $(nix build --no-link --print-out-paths $(realpath $tempdir)#bazel-dryRun)

    rm -rf $tempdir
}

drv1=$(run)
drv2=$(run)
diff -rub $drv1 $drv2
