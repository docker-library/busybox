#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")"

set -x
docker build -t busybox:builder builder
docker run --rm busybox:builder tar cC rootfs-bin . | xz -z9 > busybox.tar.xz
docker build -t busybox .
