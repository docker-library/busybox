#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")/upstream"

set -x
docker build -t busybox:builder --pull - < Dockerfile.builder
docker run --rm busybox:builder tar cC rootfs . | xz -z9 > busybox.tar.xz
docker build -t busybox .
docker run --rm busybox sh -xec 'true'
docker run --rm busybox ping -c 1 google.com
