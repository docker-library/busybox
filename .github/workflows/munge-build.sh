#!/usr/bin/env bash
set -Eeuo pipefail

jq '
	.matrix.include |= map(
		.runs.build = "./build.sh " + (.meta.entries[].directory | @sh) + "\n" + (.runs.build | sub(" --file [^ ]+ "; " "))
	)
' "$@"
