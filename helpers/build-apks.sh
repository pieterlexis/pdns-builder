#!/bin/bash
# Build multiple APKBUILDs, after installing the build dependencies

set -e # exit on helper error

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "$helpers/functions.sh"
set -x

set_apk_versions
set_python_src_versions
# TODO figure out how to inject the proper key
abuild-keygen -a

for apkbuild in "$@"; do
  # If BUILDER_PACKAGE_MATCH is set, only build the specs that match, otherwise build all
  if [ -z "$BUILDER_PACKAGE_MATCH" ] || [[ $apkbuild = *$BUILDER_PACKAGE_MATCH* ]]; then
    echo "==================================================================="
    echo "-> $apkbuild"
    cd $apkbuild
    set +e
    abuild -v -F checksum && abuild -F -r
    find .
    exit 1
    cd -
  else
    echo "Skipping APKBUILD $apkbuild (BUILDER_SKIP)"
  fi
done
