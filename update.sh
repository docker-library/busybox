#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

upstreamVersion="$(curl -fsSL --compressed 'https://busybox.net/downloads/' | grep -E '<a href="busybox-[0-9][^"/]*.tar.bz2"' | sed -r 's!.*<a href="busybox-([0-9][^"/]*).tar.bz2".*!\1!' | sort -V | tail -1)"

set -x
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$upstreamVersion"'/' */Dockerfile.builder
