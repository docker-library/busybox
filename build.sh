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
		docker run --rm "$base$version-builder" tar cC rootfs . | xz -z9 > "$version/busybox.tar.xz"
		docker build -t "$base$version-test" "$version"
		docker run --rm "$base$version-test" sh -xec 'true'
		if ! docker run --rm "$base$version-test" ping -c 1 google.com; then
			sleep 1
			docker run --rm "$base$version-test" ping -c 1 google.com
		fi
		docker images "$base$version-test"
	)
done
