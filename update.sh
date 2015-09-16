#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

upstreamVersion="$(curl -fsSL --compressed 'http://busybox.net/downloads/' | grep -E '<a href="busybox-[0-9][^"/]*.tar.bz2"' | sed -r 's!.*<a href="busybox-([0-9][^"/]*).tar.bz2".*!\1!' | sort -V | tail -1)"

ubuntuImage="$(awk 'toupper($1) == "FROM" { print $2 }' ubuntu/Dockerfile.builder)"
ubuntuVersion="$(docker run --rm ubuntu:trusty bash -c 'apt-get update -qq && apt-cache show busybox-static | awk -F ": " "\$1 == \"Version\" { print \$2; exit }"')"

set -x
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$upstreamVersion"'/;' upstream/Dockerfile.builder
sed -ri 's/^(ENV BUSYBOX_VERSION) .*/\1 '"$ubuntuVersion"'/;' ubuntu/Dockerfile.builder
#./make.sh
