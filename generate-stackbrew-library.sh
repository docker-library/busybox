#!/bin/bash
set -eu

latest='uclibc'

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

variants=( */ )
variants=( "${variants[@]%/}" )

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' --branches -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		dfCommit="$(fileCommit Dockerfile)"
		fileCommit \
			Dockerfile \
			$(git show "$dfCommit":./Dockerfile | awk '
				toupper($1) ~ /^(COPY|ADD)$/ {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

cat <<-EOH
# this file is generated via https://github.com/docker-library/busybox/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit),
             Jérôme Petazzoni <jerome@docker.com> (@jpetazzo)
GitRepo: https://github.com/docker-library/busybox.git
GitFetch: refs/heads/dist
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for variant in "${variants[@]}"; do
	[ -f "$variant/Dockerfile.builder" ] || continue

	commit="$(dirCommit "$variant")"

	fullVersion="$(git show "$commit":"$variant/Dockerfile.builder" | awk '$1 == "ENV" && $2 == "BUSYBOX_VERSION" { print $3; exit }')"

	versionAliases=()
	while [ "${fullVersion%.*}" != "$fullVersion" ]; do
		versionAliases+=( $fullVersion )
		fullVersion="${fullVersion%.*}"
	done
	versionAliases+=(
		$fullVersion
		latest
	)

	variantAliases=( "${versionAliases[@]/%/-$variant}" )
	variantAliases=( "${variantAliases[@]//latest-/}" )

	if [ "$variant" = "$latest" ]; then
		variantAliases+=( "${versionAliases[@]}" )
	fi

	echo
	cat <<-EOE
		Tags: $(join ', ' "${variantAliases[@]}")
		GitCommit: $commit
		Directory: $variant
	EOE
done
