#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

base='busybox:'
for version in "${versions[@]}"; do
	[ -f "$version/Dockerfile.builder" ] || continue
	(
		set -x
		docker build -t "$base$version-builder" -f "$version/Dockerfile.builder" "$version"
		docker run --rm "$base$version-builder" tar cC rootfs . | xz -T0 -z9 > "$version/busybox.tar.xz"
		docker build -t "$base$version-test" "$version"
		docker run --rm "$base$version-test" sh -xec 'true'

		# detect whether the current host _can_ ping
		# (QEMU user-mode networking does not route ping traffic)
		shouldPing=
		if docker run --rm "$base$version-builder" ping -c 1 google.com &> /dev/null; then
			shouldPing=1
		fi

		if [ -n "$shouldPing" ]; then
			if ! docker run --rm "$base$version-test" ping -c 1 google.com; then
				sleep 1
				docker run --rm "$base$version-test" ping -c 1 google.com
			fi
		else
			docker run --rm "$base$version-test" nslookup google.com
		fi

		docker images "$base$version-test"
	)
done
