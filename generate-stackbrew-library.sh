#!/bin/bash
set -e

declare -A prefixes=(
	[upstream]=''
	[ubuntu-trusty]='ubuntu'
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( upstream/ ubuntu-*/ )
versions=( "${versions[@]%/}" )
url='git://github.com/docker-library/busybox'

echo '# maintainer: InfoSiftr <github@infosiftr.com> (@infosiftr)'
echo '# maintainer: Jérôme Petazzoni <jerome@docker.com> (@jpetazzo)'

for version in "${versions[@]}"; do
	commit="$(cd "$version" && git log -1 --format='format:%H' -- Dockerfile $(awk 'toupper($1) == "COPY" || toupper($1) == "ADD" { for (i = 2; i < NF; i++) { print $i } }' Dockerfile))"
	fullVersion="$(grep -m1 'ENV BUSYBOX_VERSION ' "$version/Dockerfile.builder" | cut -d' ' -f3)"
	fullVersion="${fullVersion#*:}"
	fullVersion="${fullVersion%-*}"

	prefix="${prefixes[$version]:+${prefixes[$version]}-}"

	versionAliases=()
	while [ "${fullVersion%.*}" != "$fullVersion" ]; do
		versionAliases+=( $prefix$fullVersion )
		fullVersion="${fullVersion%.*}"
	done
	versionAliases+=( $prefix$fullVersion ${prefixes[$version]:-latest} )

	echo
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
