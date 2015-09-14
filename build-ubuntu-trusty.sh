#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")/ubuntu-trusty"

set -x
docker build -t busybox:ubuntu-builder --pull - < Dockerfile.builder
docker run --rm busybox:ubuntu-builder tar c . | xz -z9 > busybox.tar.xz
docker build -t busybox:ubuntu .
docker run -it --rm busybox:ubuntu sh -xec 'true'
