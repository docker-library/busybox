#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")/upstream"

set -x
docker build -t busybox:upstream-builder --pull - < Dockerfile.builder
docker run --rm busybox:upstream-builder tar cC rootfs . | xz -z9 > busybox.tar.xz
docker build -t busybox:upstream .
docker run --rm busybox:upstream sh -xec 'true'
docker run --rm busybox:upstream ping -c 1 google.com
