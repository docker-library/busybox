#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")/upstream"

set -x
docker build -t busybox:builder - < Dockerfile.builder
docker run --rm busybox:builder tar cC rootfs-bin . | xz -z9 > busybox.tar.xz
docker build -t busybox .
