#!/usr/bin/env bash
set -Eeuo pipefail

jq '
	.matrix.include |= map(
		.runs.build = (
			[
				"dir=" + (.meta.entries[].directory | @sh),
				"rm -rf \"$dir/$BASHBREW_ARCH\"", # make sure our OCI directory is clean so we can "git diff --exit-code" later
				"./build.sh \"$dir\"",
				(.runs.build | sub(" --file [^ ]+ "; " ")),
				empty
			] | join("\n")
		)
	)
' "$@"
