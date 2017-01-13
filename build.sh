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
		docker build -t "$base$version-builder" --pull -f "$version/Dockerfile.builder" "$version"
		docker run --rm "$base$version-builder" tar cC rootfs . | xz -z9 > "$version/busybox.tar.xz"
		docker build -t "$base$version" "$version"
		docker run --rm "$base$version" sh -xec 'true'
		docker run --rm "$base$version" ping -c 1 google.com
	)
done
