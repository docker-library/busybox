#!/usr/bin/env bash
set -Eeuo pipefail

jq '
	.matrix.include |= map(
		(.name | contains("i386")) as $i386
		| if $i386 and (.name | contains("uclibc")) then empty else . end # uclibc builds are heavy; do not test i386/uclibc on GHA
		| .BASHBREW_ARCH = (if $i386 then "i386" else "amd64" end)
		| .runs.build = (
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
