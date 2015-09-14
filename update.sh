#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

upstreamVersion="$(curl -fsSL --compressed 'http://busybox.net/downloads/' | grep -E '<a href="busybox-[0-9][^"/]*.tar.bz2"' | sed -r 's!.*<a href="busybox-([0-9][^"/]*).tar.bz2".*!\1!' | sort -V | tail -1)"
trustyVersion="$(curl -fsSL 'https://mirrors.xmission.com/ubuntu/dists/trusty/main/binary-amd64/Packages.bz2' | bunzip2 | awk -F ': ' '$1 == "Package" { pkg = $2 } pkg == "busybox-static" && $1 == "Version" { print $2 }')"

set -x
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$upstreamVersion"'/;' upstream/Dockerfile.builder
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$trustyVersion"'/;' ubuntu-trusty/Dockerfile.builder
#./make.sh
