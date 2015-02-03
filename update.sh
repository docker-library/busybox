#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

fullVersion="$(curl -sSL --compressed 'http://busybox.net/downloads/' | grep -E '<a href="busybox-[0-9][^"/]*.tar.bz2"' | sed -r 's!.*<a href="busybox-([0-9][^"/]*).tar.bz2".*!\1!' | sort -V | tail -1)"

set -x
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$fullVersion"'/;' upstream/Dockerfile.builder
./make.sh
