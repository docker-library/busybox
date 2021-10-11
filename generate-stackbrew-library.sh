#!/usr/bin/env bash
set -Eeuo pipefail

gitHubUrl='https://github.com/docker-library/busybox'
rawGitUrl="$gitHubUrl/raw"

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

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
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
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

# if stable is 1.32.1 and unstable is 1.33.0, we want busybox:1.33 to point to unstable but busybox:1 (and busybox:latest) to point to stable
# since stable always comes first, we'll just let it take all the tags it calculates, and use this to remove any overlap when we process unstable :)
declare -A usedTags=()
_tags() {
	local tag first=
	for tag; do
		[ -z "${usedTags[$tag]:-}" ] || continue
		usedTags[$tag]=1
		if [ -z "$first" ]; then
			echo
			echo -n 'Tags: '
			first=1
		else
			echo -n ', '
		fi
		echo -n "$tag"
	done
	if [ -z "$first" ]; then
		return 1
	fi
	echo
	return 0
}

allVersions=()
for version; do
	export version

	variants="$(jq -r '.[env.version].variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	fullVersion="$(jq -r '.[env.version].version' versions.json)"
	allVersions+=( "$fullVersion" )
	latestVersion="$(xargs -n1 <<<"${allVersions[*]}" | sort -V | tail -1)"
	if [ "$latestVersion" != "$fullVersion" ]; then
		# if "unstable" is older than "stable" (1.32.0 unstable vs 1.32.1 stable, for example), skip unstable
		continue
	fi

	versionAliases=()
	while [ "${fullVersion%.*}" != "$fullVersion" ]; do
		versionAliases+=( $fullVersion )
		fullVersion="${fullVersion%.*}"
	done
	versionAliases+=(
		$fullVersion
		$version # "stable", "unstable"
		latest
	)

	declare -A archLatestDir=()
	for variant in "${variants[@]}"; do
		dir="$version/$variant"

		variantAliases=( "${versionAliases[@]/%/-$variant}" )
		variantAliases=( "${variantAliases[@]//latest-/}" )

		variantArches=()
		for arch in "${arches[@]}"; do
			archCommit="${archCommits[$arch]}"
			if wget --quiet --spider -O /dev/null -o /dev/null "$rawGitUrl/$archCommit/$dir/busybox.tar.xz"; then
				variantArches+=( "$arch" )
				: "${archLatestDir[$arch]:=$dir}" # record the first supported directory per architecture for "latest" and friends
			fi
		done

		if _tags "${variantAliases[@]}"; then
			cat <<-EOE
				Architectures: $(join ', ' "${variantArches[@]}")
				Directory: $dir
			EOE
		fi
	done

	if _tags "${versionAliases[@]}"; then
		cat <<-EOE
			Architectures: $(join ', ' "${arches[@]}")
		EOE
		for arch in "${arches[@]}"; do
			archDir="${archLatestDir[$arch]}"
			cat <<-EOA
				${arch}-Directory: $archDir
			EOA
		done
	fi
done
