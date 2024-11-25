#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ "${#versions[@]}" -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

busyboxVersions="$(
	wget -qO- 'https://busybox.net' \
		| grep -oE '[0-9a-zA-Z ]+ -- BusyBox [0-9.]+ [(](un)?stable[)]' \
		| jq -csR '
			rtrimstr("\n")
			| split("\n")
			| map(
				split(" -- BusyBox ")
				| {
					version: .[1],
					date: .[0],
				}
				| .stability = (.version | gsub(".* [(]|[)]"; ""))
				| .version |= split(" ")[0]
			)
			| sort_by(.version | split(".") | map(tonumber))
			| reverse
		'
)"
# [
#  {
#    "version": "1.36.0",
#    "date": "3 January 2023",
#    "stability": "unstable"
#  },
#  ...
# ]

buildrootVersion="$(
	git ls-remote --tags https://gitlab.com/buildroot.org/buildroot.git \
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

	minus="${version#latest}"
	minus="${minus#-}"
	: "${minus:=0}"
	majorMinor="$(jq <<<"$busyboxVersions" -cr --argjson minus "$minus" '
		map(.version | split(".")[0:2] | join("."))
		| unique
		| reverse[$minus]
	')"
	if [ -z "$majorMinor" ]; then
		echo >&2 "error: failed to find '$version' release"
		exit 1
	fi
	doc="$(jq <<<"$busyboxVersions" -c --arg majorMinor "$majorMinor" '
		map(select(
			.version
			| startswith($majorMinor + ".")
		))[0]
	')"

	fullVersion="$(jq <<<"$doc" -r '.version')"
	export fullVersion

	echo "$version: $fullVersion (buildroot $buildrootVersion)"

	sha256="$(wget -qO- "https://busybox.net/downloads/busybox-$fullVersion.tar.bz2.sha256" | cut -d' ' -f1)"
	export sha256

	json="$(
		jq <<<"$json" -c --argjson doc "$doc" '
			.[env.version] = $doc + {
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
