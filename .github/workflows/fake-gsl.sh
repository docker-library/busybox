#!/usr/bin/env bash
set -Eeuo pipefail

# this is a fake version of "generate-stackbrew-library.sh" just so https://github.com/docker-library/bashbrew/blob/c74be66ae6a019e0baee601287187dc6df29b384/scripts/github-actions/generate.sh can generate us a sane starter matrix

[ -f versions.json ] # run "versions.sh" first

if [ "$#" -eq 0 ]; then
	dirs="$(jq -r 'to_entries | map(.key + "/" + (.value.variants[])) | map(@sh) | join(" ")' versions.json)"
	eval "set -- $dirs"
fi

echo 'Maintainers: foo (@bar)'
echo 'GitRepo: https://github.com/docker-library/busybox.git'
commit="$(git log -1 --format='format:%H')"
echo "GitCommit: $commit"

for d; do
	echo
	echo "Tags: ${d////-}"
	echo "Directory: $d"
	echo "File: Dockerfile.builder"
done
