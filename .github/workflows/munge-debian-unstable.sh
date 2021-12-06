#!/usr/bin/env bash
set -Eeuo pipefail

jq '
	.matrix.include += [
		.matrix.include[]
		| select(.name | test(" [(].+[)]") | not) # ignore any existing munged builds
		| select(.os | startswith("windows-") | not)
		| select(.meta.froms | any(startswith("debian:")))
		| .name += " (debian:unstable)"
		| .runs.pull = ([
			"# pull debian:unstable variants of base images for Debian Ports architectures",
			"# https://github.com/docker-library/oi-janky-groovy/blob/0f8796a8aeedca90aba0a7e102f35ea172a23bb3/tianon/busybox/arch-pipeline.groovy#L68-L71",
			(
				.meta.froms[]
				| (sub(":[^-]+"; ":unstable") | @sh) as $img
				| (
					"docker pull " + $img,
					"docker tag " + $img + " " + @sh
				)
			)
		] | join("\n"))
	]
' "$@"
