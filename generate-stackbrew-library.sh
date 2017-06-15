#!/bin/bash
set -Eeuo pipefail

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

gitHubUrl='https://github.com/docker-library/busybox'
#rawGitUrl="$gitHubUrl/raw"
rawGitUrl="${gitHubUrl//github.com/cdn.rawgit.com}" # we grab a lot of tiny files, and rawgit's CDN is more consistently speedy on a cache hit than GitHub's

# prefer uclibc, but if it's unavailable use glibc if possible since it's got less "edge case" behavior, especially around DNS
variants=(
	uclibc
	glibc
	musl
)
# (order here determines "preference" for representing "latest")

archMaps=( $(
	git ls-remote --heads "${gitHubUrl}.git" \
		| awk -F '[\t/]' '$4 ~ /^dist-/ { gsub(/^dist-/, "", $4); print $4 "=" $1 }' \
		| sort
) )
arches=()
declare -A archCommits=()
for archMap in "${archMaps[@]}"; do
	arch="${archMap%%=*}"
	commit="${archMap#${arch}=}"
	arches+=( "$arch" )
	archCommits[$arch]="$commit"
done

selfCommit="$(git log --format='format:%H' -1)"
cat <<-EOH
# this file is generated via $gitHubUrl/blob/$selfCommit/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit),
             Jérôme Petazzoni <jerome@docker.com> (@jpetazzo)
GitRepo: $gitHubUrl.git
GitCommit: $selfCommit
EOH
for arch in "${arches[@]}"; do
	commit="${archCommits[$arch]}"
	cat <<-EOA
		# $gitHubUrl/tree/dist-${arch}
		${arch}-GitFetch: refs/heads/dist-${arch}
		${arch}-GitCommit: $commit
	EOA
done

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

# pre-flight sanity checks
fullVersion=
for variant in "${variants[@]}"; do
	[ -f "$variant/Dockerfile.builder" ]
	oldVersion="$fullVersion"
	fullVersion="$(awk '$1 == "ENV" && $2 == "BUSYBOX_VERSION" { print $3; exit }' "$variant/Dockerfile.builder")"
	[ -n "$fullVersion" ]
	[ "$fullVersion" = "${oldVersion:-$fullVersion}" ]
done
versionAliases=()
while [ "${fullVersion%.*}" != "$fullVersion" ]; do
	versionAliases+=( $fullVersion )
	fullVersion="${fullVersion%.*}"
done
versionAliases+=(
	$fullVersion
	latest
)

declare -A archLatest=()
for variant in "${variants[@]}"; do
	variantAliases=( "${versionAliases[@]/%/-$variant}" )
	variantAliases=( "${variantAliases[@]//latest-/}" )

	variantArches=()
	for arch in "${arches[@]}"; do
		archCommit="${archCommits[$arch]}"
		if wget --quiet --spider -O /dev/null -o /dev/null "$rawGitUrl/$archCommit/$variant/busybox.tar.xz"; then
			variantArches+=( "$arch" )
			if [ -z "${archLatest[$arch]:-}" ]; then
				archLatest[$arch]="$variant"
			fi
		fi
	done

	echo
	cat <<-EOE
		Tags: $(join ', ' "${variantAliases[@]}")
		Architectures: $(join ', ' "${variantArches[@]}")
		Directory: $variant
	EOE
done

echo
cat <<-EOE
	Tags: $(join ', ' "${versionAliases[@]}")
	Architectures: $(join ', ' "${arches[@]}")
EOE
for arch in "${arches[@]}"; do
	archVariant="${archLatest[$arch]}"
	cat <<-EOA
		${arch}-Directory: $archVariant
	EOA
done
