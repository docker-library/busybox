#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )
url='git://github.com/docker-library/busybox'

echo '# maintainer: InfoSiftr <github@infosiftr.com> (@infosiftr)'
echo '# maintainer: Jérôme Petazzoni <jerome@docker.com> (@jpetazzo)'

for version in "${versions[@]}"; do
	commit="$(cd "$version" && git log -1 --format='format:%H' -- Dockerfile $(awk 'toupper($1) == "COPY" || toupper($1) == "ADD" { for (i = 2; i < NF; i++) { print $i } }' Dockerfile))"
	fullVersion="$(grep -m1 'ENV BUSYBOX_VERSION ' "$version/Dockerfile.builder" | cut -d' ' -f3)"
	fullVersion="${fullVersion#*:}"
	fullVersion="${fullVersion%-*}"

	verSuffix="$version"
	if [ "$version" = 'upstream' ]; then
		verSuffix=''
	fi
	suffix="${verSuffix:+-$verSuffix}"

	versionAliases=()
	while [ "${fullVersion%.*}" != "$fullVersion" ]; do
		versionAliases+=( $fullVersion$suffix )
		fullVersion="${fullVersion%.*}"
	done
	versionAliases+=( $fullVersion$suffix ${verSuffix:-latest} )

	echo
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
