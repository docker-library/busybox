#!/usr/bin/env bash
set -Eeuo pipefail

# this is a fake version of "generate-stackbrew-library.sh" just so https://github.com/docker-library/bashbrew/blob/c74be66ae6a019e0baee601287187dc6df29b384/scripts/github-actions/generate.sh can generate us a sane starter matrix

echo 'Maintainers: foo (@bar)'
echo 'GitRepo: https://github.com/docker-library/busybox.git'
for f in */Dockerfile.builder; do
	d="$(dirname "$f")"
	commit="$(git log -1 --format='format:%H' "$d/Dockerfile")"
	echo
	echo "Tags: $d"
	echo "Directory: $d"
	echo "GitCommit: $commit"
done
