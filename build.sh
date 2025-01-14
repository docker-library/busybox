#!/usr/bin/env bash
set -Eeuo pipefail

[ -f versions.json ] # run "versions.sh" first

if [ "$#" -eq 0 ]; then
	dirs="$(jq -r 'to_entries | map(.key + "/" + (.value.variants[])) | map(@sh) | join(" ")' versions.json)"
	eval "set -- $dirs"
fi

[ -n "$BASHBREW_ARCH" ]
platformString="$(bashbrew cat --format '{{ ociPlatform arch }}' <(echo 'Maintainers: empty hack (@example)'))"
platform="$(bashbrew cat --format '{{ ociPlatform arch | json }}' <(echo 'Maintainers: empty hack (@example)'))"

for dir; do
	variant="$(basename "$dir")"
	base="busybox:${dir////-}-$BASHBREW_ARCH"

	froms="$(awk 'toupper($1) == "FROM" { print $2 }' "$dir/Dockerfile.builder")"
	for from in "$froms"; do
		if ! bashbrew remote arches --json "$from" | jq -e '.arches | has(env.BASHBREW_ARCH)' > /dev/null; then
			echo >&2 "warning: '$base' is 'FROM $from' which does not support '$BASHBREW_ARCH'; skipping"
			continue 2
		fi
	done

	(
		set -x

		# TODO save the output of "bashbrew remote arches" above so we can "--build-context" here?
		docker buildx build \
			--progress=plain \
			--platform "$platformString" \
			--pull \
			--load \
			--tag "$base-builder" \
			--file "$dir/Dockerfile.builder" \
			. # context is "." so we can access the (shared) ".patches" directory

		oci="$dir/$BASHBREW_ARCH"
		rm -rf "$oci"
		mkdir "$oci" "$oci/blobs" "$oci/blobs/sha256"

		docker run --rm "$base-builder" \
			tar \
				--create \
				--directory rootfs \
				--numeric-owner \
				--transform 's,^./,,' \
				--sort name \
				--mtime /usr/src/busybox.SOURCE_DATE_EPOCH --clamp-mtime \
				. \
				> "$oci/rootfs.tar"

		# if we gzip separately, we can calculate the diffid without decompressing
		diffId="$(sha256sum "$oci/rootfs.tar" | cut -d' ' -f1)"
		diffId="sha256:$diffId"

		# we need to use the container's gzip so it's more likely reproducible over time (and using busybox's own gzip is a cute touch 😀)
		docker run -i --rm "$base-builder" chroot rootfs gzip -c < "$oci/rootfs.tar" > "$oci/rootfs.tar.gz"
		rm "$oci/rootfs.tar"
		rootfs="$(sha256sum "$oci/rootfs.tar.gz" | cut -d' ' -f1)"
		ln -svfT --relative "$oci/rootfs.tar.gz" "$oci/blobs/sha256/$rootfs"
		rootfsSize="$(stat --format '%s' --dereference "$oci/blobs/sha256/$rootfs")"
		rootfs="sha256:$rootfs"

		SOURCE_DATE_EPOCH="$(docker run --rm "$base-builder" cat /usr/src/busybox.SOURCE_DATE_EPOCH)"
		createdBy="$(docker run --rm --env variant="$variant" "$base-builder" sh -euc '. /etc/os-release && echo "BusyBox $BUSYBOX_VERSION ($variant)${BUILDROOT_VERSION:+, Buildroot $BUILDROOT_VERSION}, ${NAME%% *} ${VERSION_ID:-$VERSION_CODENAME}"')"
		jq -n --tab --arg SOURCE_DATE_EPOCH "$SOURCE_DATE_EPOCH" --arg diffId "$diffId" --arg createdBy "$createdBy" --argjson platform "$platform" '
			($SOURCE_DATE_EPOCH | tonumber | strftime("%Y-%m-%dT%H:%M:%SZ")) as $created
			| {
				config: {
					Cmd: [ "sh" ],
					Env: [ "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ],
				},
				created: $created,
				history: [ {
					created: $created,
					created_by: $createdBy,
				} ],
				rootfs: {
					type: "layers",
					diff_ids: [ $diffId ],
				},
			} + $platform
		' > "$oci/image-config.json"
		config="$(sha256sum "$oci/image-config.json" | cut -d' ' -f1)"
		ln -svfT --relative "$oci/image-config.json" "$oci/blobs/sha256/$config"
		configSize="$(stat --format '%s' --dereference "$oci/blobs/sha256/$config")"
		config="sha256:$config"

		version="$(cut <<<"$createdBy" -d' ' -f2)" # a better way to scrape the BusyBox version?  maybe this is fine (want to avoid yet another container run)
		jq -n --tab --arg version "$version" --arg variant "$variant" --arg config "$config" --arg configSize "$configSize" --arg rootfs "$rootfs" --arg rootfsSize "$rootfsSize" '
			{
				schemaVersion: 2,
				mediaType: "application/vnd.oci.image.manifest.v1+json",
				config: {
					mediaType: "application/vnd.oci.image.config.v1+json",
					digest: $config,
					size: ($configSize | tonumber),
				},
				layers: [ {
					mediaType: "application/vnd.oci.image.layer.v1.tar+gzip",
					digest: $rootfs,
					size: ($rootfsSize | tonumber),
				} ],
				annotations: {
					"org.opencontainers.image.url": "https://github.com/docker-library/busybox",
					"org.opencontainers.image.version": ($version + "-" + $variant),
				},
			}
		' > "$oci/image-manifest.json"
		manifest="$(sha256sum "$oci/image-manifest.json" | cut -d' ' -f1)"
		ln -svfT --relative "$oci/image-manifest.json" "$oci/blobs/sha256/$manifest"
		manifestSize="$(stat --format '%s' --dereference "$oci/blobs/sha256/$manifest")"
		manifest="sha256:$manifest"

		jq -nc '{ imageLayoutVersion:"1.0.0" }' > "$oci/oci-layout"
		jq -n --tab --arg version "$version" --arg variant "$variant" --arg manifest "$manifest" --arg manifestSize "$manifestSize" --argjson platform "$platform" '
			{
				schemaVersion: 2,
				mediaType: "application/vnd.oci.image.index.v1+json",
				manifests: [ {
					mediaType: "application/vnd.oci.image.manifest.v1+json",
					digest: $manifest,
					size: ($manifestSize | tonumber),
					platform: $platform,
					annotations: {
						"org.opencontainers.image.ref.name": ("busybox:" + $version + "-" + $variant),
						"io.containerd.image.name": ("busybox:" + $version + "-" + $variant),
					},
				} ],
			}
		' > "$oci/index.json"

		ln -svfT --relative "$oci/rootfs.tar.gz" "$dir/busybox.tar.gz"
		docker build -t "$base-test" "$dir"
		docker run --rm "$base-test" sh -xec 'true'

		# detect whether the current host _can_ ping
		# (QEMU user-mode networking does not route ping traffic)
		shouldPing=
		if docker run --rm "$base-builder" ping -c 1 google.com &> /dev/null; then
			shouldPing=1
		fi

		if [ -n "$shouldPing" ]; then
			if ! docker run --rm "$base-test" ping -c 1 google.com; then
				sleep 1
				docker run --rm "$base-test" ping -c 1 google.com
			fi
		else
			docker run --rm "$base-test" nslookup google.com
		fi

		docker images "$base-test"
	)
done
