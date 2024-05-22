#!/usr/bin/env bash
set -Eeuo pipefail

# see also "hack-unstable.sh"
jq '
	.matrix.include += [
		.matrix.include[]
		| select(.name | test(" [(].+[)]") | not) # ignore any existing munged builds
		| select(.os | startswith("windows-") | not)
		| select(.meta.froms | any(startswith("debian:")))
		| .name += " (unstable)"
		| .runs.prepare += ([
			"./hack-unstable.sh " + (.meta.entries[].directory | @sh),
			"if git diff --exit-code; then exit 1; fi", # trust, but verify (if hack-unstable did not modify anything, we want to bail quickly)
			empty
		] | map("\n" + .) | add)
		| .runs.pull = "" # pulling images does not make sense here (we just changed them)
	]
' "$@"
