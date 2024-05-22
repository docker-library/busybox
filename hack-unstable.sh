#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -eq 0 ]; then
	set -- */*/
fi

set -x

# This is used to modify "Dockerfile.builder" for architectures that are not (yet) supported by stable releases (notably, riscv64).
sed -ri \
	-e 's/^(FROM debian:)[^ -]+/\1unstable/g' \
	"${@/%//Dockerfile.builder}"
