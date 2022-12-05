#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ "${#versions[@]}" -eq 0 ]; then
	versions=( stable unstable )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

busyboxVersions="$(
	wget -qO- 'https://busybox.net' \
		| grep -ioE ' -- BusyBox [0-9.]+ [(](un)?stable[)]' \
		| cut -d' ' -f4- \
		| sort -rV
)"
# "1.32.1 (stable)"
# "1.33.0 (unstable)"
# ...

buildrootVersion="$(
	git ls-remote --tags https://git.busybox.net/buildroot \
		| cut -d/ -f3 \
		| cut -d^ -f1 \
		| grep -E '^[0-9]+' \
		| grep -vE -- '[-_]rc' \
		| sort -uV \
		| tail -1
)"
export buildrootVersion

for version in "${versions[@]}"; do
	export version

	if ! fullVersion="$(grep -m1 -F " ($version)" <<<"$busyboxVersions")" || [ -z "$fullVersion" ]; then
		echo >&2 "error: failed to find latest '$version' release"
		exit 1
	fi
	fullVersion="${fullVersion%% *}"
	export fullVersion

	sha256="$(wget -qO- "https://busybox.net/downloads/busybox-$fullVersion.tar.bz2.sha256" | cut -d' ' -f1)"
	export sha256

	echo "$version: $fullVersion"

	json="$(
		jq <<<"$json" -c '
			.[env.version] = {
				version: env.fullVersion,
				sha256: env.sha256,
				buildroot: {
					version: env.buildrootVersion,
				},
				# as of buildroot 2022.11, glibc is the default, so we follow suit (https://github.com/buildroot/buildroot/commit/4057e36ca9665edd5248512e4edba2c243b8f4be)
				# https://busybox.net/FAQ.html#libc
				variants: [ "glibc", "uclibc", "musl" ],
				# (order here determines "preference" for representing "latest")
			}
		'
	)"
done

jq <<<"$json" -S . > versions.json
