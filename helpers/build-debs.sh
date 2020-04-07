#!/bin/bash
# Build debian packages, after installing dependencies
# This assumes the the source is unpacked and a debian/ directory exists

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "$helpers/functions.sh"

debunpackdir=/packages
mkdir -p $debunpackdir

function debdir_hash {
  local debdir="$1/debian"
  local n=$(basename "$1")
  local h=$(sha1sum $(find $debdir -type f -maxdepth 1 | LC_ALL=C sort) | sha1sum | awk '{print $1}')
  echo "$n.$h"
}

function new_debs {
  diff -u /tmp/debs-before /tmp/debs-after | tee /tmp/debs-diff | grep -v '^[+][+]' | grep '^[+]' | sed 's/^[+]//'
}

function deb_file_list {
  find "$debunpackdir" -type f | sed "s|${debunpackdir}/||" | LC_ALL=C sort
}

function check_cache {
  local pkgname="$(dirname $1)"
  local h=$(debdir_hash "$1")
  if [ -f "/cache/old/${h}.tar" ]; then
    echo "* FOUND IN CACHE: $pkgname"
    tar -C "${debunpackdir}" -xvf "/cache/old/$h.tar"
    return 0
  fi
  return 1
}

cache=
if [ ! -z "$BUILDER_CACHE" ] && [ ! -z "$BUILDER_CACHE_THIS" ]; then
    cache=1
    mkdir -p /cache/new
fi

declare -A skip_debs # associative array (dict)
dirs=()
for dir in "$@"; do
  # If BUILDER_PACKAGE_MATCH is set, only build the packages that match, otherwise build all
  if [ -z "$BUILDER_PACKAGE_MATCH" ] || [[ $dir = *$BUILDER_PACKAGE_MATCH* ]]; then
    if [ ! -d ${dir}/debian ]; then
      echo "${dir}/debian does not exist, can not build!"
      continue
    fi
    if [ "$cache" = "1" ] && check_cache "$dir"; then
      skip_debs[$dir]=1
      echo "::: $dir (cached)"
      continue
    fi
    dirs+=($dir)
  fi
done

if [ "${#dirs[@]}" = "0" ]; then
    echo "No debian package directories matched, nothing to do"
    exit 0
fi

for dir in "${dirs[@]}"; do
  # Install all build-deps
  pushd "${dir}"
  mk-build-deps -i -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' || exit 1
  popd
done

for dir in "${dirs[@]}"; do
  # hash _before_ building as we don't want changed dirs
  h=$(debdir_hash "${dir}")

  echo "==================================================================="
  echo "-> ${dir}"
  pushd "${dir}"
  # If there's a changelog, this is probably a vendor dependency or versioned
  # outside of pdns-builder
  if [ ! -f debian/changelog ]; then
    # Parse the Source name
    sourcename=`grep '^Source: ' debian/control | sed 's,^Source: ,,'`
    if [ -z "${sourcename}" ]; then
      echo "Unable to parse name of the source from ${dir}"
      exit 1
    fi
    # Let's try really hard to find the release name of the distribution
    distro_release="$(source /etc/os-release; printf ${VERSION_CODENAME})"
    if [ -z "${distro_release}" -a -n "$(grep 'VERSION_ID="14.04"' /etc/os-release)" ]; then
      distro_release='trusty'
    fi
    if [ -z "${distro_release}" ]; then
      distro_release="$(perl -n -e '/VERSION=".* \((.*)\)"/ && print $1' /etc/os-release)"
    fi
    if [ -z "${distro_release}" ]; then
      distro_release="$(perl -n -e '/PRETTY_NAME="Debian GNU\/Linux (.*)\/sid"/ && print $1' /etc/os-release)"
    fi
    if [ -z "${distro_release}" ]; then
      echo 'Unable to determine distribution codename!'
      exit 1
    fi
    if [ -z "$BUILDER_EPOCH" ]; then
      epoch_string=""
    else
      epoch_string="${BUILDER_EPOCH}:"
    fi
    echo "EPOCH_STRING=${epoch_string}"
    set_debian_versions
    cat > debian/changelog << EOF
$sourcename (${epoch_string}${BUILDER_DEB_VERSION}-${BUILDER_DEB_RELEASE}.${distro_release}) unstable; urgency=medium

  * Automatic build

 -- PowerDNS.COM AutoBuilder <noreply@powerdns.com>  $(date -R)
EOF
  fi

  deb_file_list > /tmp/debs-before
  fakeroot debian/rules binary || exit 1

  if [ "$cache" = "1" ]; then
    pushd ..
    set -x
    cp *.deb $debunpackdir
    cp *.ddeb $debunpackdir || true
    deb_file_list > /tmp/debs-after
    new_debs | sed 's/^/NEW: /'
    cat /tmp/debs-diff | sed 's/^/DIFF: /'

    tar -C "$debunpackdir" -cvf "/cache/new/$h.tar" $(new_debs)
    popd
  fi
  popd
done
