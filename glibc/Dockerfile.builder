FROM debian:stretch-slim

# nolog-unless-err inspired by https://anonscm.debian.org/cgit/collab-maint/devscripts.git/plain/scripts/annotate-output.sh?id=a3f68458f2e24e13bc7cd280d348f3c5861af2c8
RUN { \
	echo '#!/bin/bash'; \
	echo 'set -e'; \
	echo; \
	echo 'OUT_DESC="stdout: "'; \
	echo 'ERR_DESC="stderr: "'; \
	echo; \
	echo 'TMP_DIR="$(mktemp -d)"'; \
	echo 'COM_LOG="$TMP_DIR/log"'; \
	echo 'OUT_FIFO="$TMP_DIR/out"'; \
	echo 'ERR_FIFO="$TMP_DIR/err"'; \
	echo; \
	echo 'cleanup() { rm -r "$TMP_DIR"; }'; \
	echo 'trap "cleanup" EXIT'; \
	echo; \
	echo 'error() {'; \
	echo '	awk "'; \
	echo '		function work(tt, dst) {'; \
# hacky sleep due to Docker race conditions where stderr and stdout get muxed wrong
# for example: echo hi; echo >&2 hello; echo hi again
# often, this will come out as:
#   hello
#   hi
#   hi again
# rather than "hello" being between the two stdout
# (if we switch between stdout/stderr 15+ times in a single RUN, just give up trying to fix the race and prefer speed instead)
# see https://github.com/docker/docker/issues/31706
	echo '			if (t != tt && t != 0 && wtf < 15) {'; \
	echo '				system(\"sleep 1\")'; \
	echo '				wtf++'; \
	echo '			}'; \
	echo '			print > dst'; \
	echo '			fflush(dst)'; \
	echo '			t = tt'; \
	echo '		}'; \
	echo '		/^$OUT_DESC/ { gsub(/^$OUT_DESC/, \"\"); work(1, \"/dev/stdout\"); next }'; \
	echo '		/^$ERR_DESC/ { gsub(/^$ERR_DESC/, \"\"); work(2, \"/dev/stderr\"); next }'; \
	echo '	" "$COM_LOG"'; \
	echo '}'; \
	echo 'trap "error" ERR'; \
	echo; \
	echo 'mkfifo "$OUT_FIFO" "$ERR_FIFO"'; \
	echo; \
	echo 'prefixOutput() {'; \
	echo '	while IFS= read -r line; do printf "%s%s\\n" "$1" "$line"; done'; \
	echo '	if [ ! -z "$line" ]; then printf "%s%s\\n" "$1" "$line"; fi'; \
	echo '}'; \
	echo 'exec 42>"$COM_LOG"'; \
	echo 'prefixOutput "$OUT_DESC" < "$OUT_FIFO" >&42 &'; \
	echo 'prefixOutput "$ERR_DESC" < "$ERR_FIFO" >&42 &'; \
# write some bits on a loop to communicate our "aliveness"
	echo 'while true; do sleep 60; echo -n .; done &'; \
	echo; \
	echo 'sh -ec "$*" >"$OUT_FIFO" 2>"$ERR_FIFO"'; \
	} > /usr/local/bin/nolog-unless-err \
	&& chmod +x /usr/local/bin/nolog-unless-err

SHELL [ "nolog-unless-err" ]

RUN apt-get update && apt-get install -y \
		bzip2 \
		curl \
		gcc \
		gnupg dirmngr \
		make \
	&& rm -rf /var/lib/apt/lists/*

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

ENV BUSYBOX_VERSION 1.30.1

RUN set -ex; \
	tarball="busybox-${BUSYBOX_VERSION}.tar.bz2"; \
	curl -fL -o busybox.tar.bz2 "https://busybox.net/downloads/$tarball"; \
	curl -fL -o busybox.tar.bz2.sig "https://busybox.net/downloads/$tarball.sig"; \
	gpg --batch --verify busybox.tar.bz2.sig busybox.tar.bz2; \
	mkdir -p /usr/src/busybox; \
	tar -xf busybox.tar.bz2 -C /usr/src/busybox --strip-components 1; \
	rm busybox.tar.bz2*

WORKDIR /usr/src/busybox

# CONFIG_LAST_SUPPORTED_WCHAR: see https://github.com/docker-library/busybox/issues/13 (UTF-8 input)
# As long as we rely on libnss, we have to have libc.so anyhow, so
# we've removed CONFIG_STATIC here for now... :cry:
RUN set -ex; \
	\
	setConfs=' \
		CONFIG_AR=y \
		CONFIG_FEATURE_AR_CREATE=y \
		CONFIG_FEATURE_AR_LONG_FILENAMES=y \
		CONFIG_LAST_SUPPORTED_WCHAR=0 \
	'; \
	\
	unsetConfs=' \
		CONFIG_FEATURE_SYNC_FANCY \
	'; \
	\
	make defconfig; \
	\
	for conf in $unsetConfs; do \
		sed -i \
			-e "s!^$conf=.*\$!# $conf is not set!" \
			.config; \
	done; \
	\
	for confV in $setConfs; do \
		conf="${confV%=*}"; \
		sed -i \
			-e "s!^$conf=.*\$!$confV!" \
			-e "s!^# $conf is not set\$!$confV!" \
			.config; \
		if ! grep -q "^$confV\$" .config; then \
			echo "$confV" >> .config; \
		fi; \
	done; \
	\
	make oldconfig; \
	\
# trust, but verify
	for conf in $unsetConfs; do \
		! grep -q "^$conf=" .config; \
	done; \
	for confV in $setConfs; do \
		grep -q "^$confV\$" .config; \
	done;

RUN set -ex \
	&& make -j "$(nproc)" \
		busybox \
	&& ./busybox --help \
	&& mkdir -p rootfs/bin \
	&& ln -vL busybox rootfs/bin/ \
	\
	&& ln -vL "$(which getconf)" rootfs/bin/getconf \
	\
# hack hack hack hack hack
# with glibc, static busybox uses libnss for DNS resolution :(
	&& mkdir -p rootfs/etc \
	&& cp /etc/nsswitch.conf rootfs/etc/ \
	&& mkdir -p rootfs/lib \
	&& ln -sT lib rootfs/lib64 \
	&& set -- \
		rootfs/bin/busybox \
		rootfs/bin/getconf \
		/lib/"$(gcc -print-multiarch)"/libnss*.so.* \
# libpthread is part of glibc: http://stackoverflow.com/a/11210463/433558
		/lib/"$(gcc -print-multiarch)"/libpthread*.so.* \
	&& while [ "$#" -gt 0 ]; do \
		f="$1"; shift; \
		fn="$(basename "$f")"; \ 
		if [ -e "rootfs/lib/$fn" ]; then continue; fi; \
		if [ "${f#rootfs/}" = "$f" ]; then \
			if [ "${fn#ld-}" = "$fn" ]; then \
				ln -vL "$f" "rootfs/lib/$fn"; \
			else \
				cp -v "$f" "rootfs/lib/$fn"; \
			fi; \
		fi; \
		set -- "$@" $(ldd "$f" | awk ' \
			$1 ~ /^\// { print $1; next } \
			$2 == "=>" && $3 ~ /^\// { print $3; next } \
		'); \
	done \
	\
	&& chroot rootfs /bin/getconf _NPROCESSORS_ONLN \
	\
	&& chroot rootfs /bin/busybox --install /bin

# download a few extra files from buildroot (/etc/passwd, etc)
RUN set -ex; \
	buildrootVersion='2019.02.1'; \
	mkdir -p rootfs/etc; \
	for f in passwd shadow group; do \
		curl -fL -o "rootfs/etc/$f" "https://git.busybox.net/buildroot/plain/system/skeleton/etc/$f?id=$buildrootVersion"; \
	done; \
# set expected permissions, etc too (https://git.busybox.net/buildroot/tree/system/device_table.txt)
	curl -fL -o buildroot-device-table.txt "https://git.busybox.net/buildroot/plain/system/device_table.txt?id=$buildrootVersion"; \
	awk ' \
		!/^#/ { \
			if ($2 != "d" && $2 != "f") { \
				printf "error: unknown type \"%s\" encountered in line %d: %s\n", $2, NR, $0 > "/dev/stderr"; \
				exit 1; \
			} \
			sub(/^\/?/, "rootfs/", $1); \
			if ($2 == "d") { \
				printf "mkdir -p %s\n", $1; \
			} \
			printf "chmod %s %s\n", $3, $1; \
		} \
	' buildroot-device-table.txt | bash -Eeuo pipefail -x; \
	rm buildroot-device-table.txt

# create missing home directories
RUN set -ex \
	&& cd rootfs \
	&& for userHome in $(awk -F ':' '{ print $3 ":" $4 "=" $6 }' etc/passwd); do \
		user="${userHome%%=*}"; \
		home="${userHome#*=}"; \
		home="./${home#/}"; \
		if [ ! -d "$home" ]; then \
			mkdir -p "$home"; \
			chown "$user" "$home"; \
			chmod 755 "$home"; \
		fi; \
	done

# test and make sure it works
RUN chroot rootfs /bin/sh -xec 'true'

# ensure correct timezone (UTC)
RUN set -ex; \
	ln -vL /usr/share/zoneinfo/UTC rootfs/etc/localtime; \
	[ "$(chroot rootfs date +%Z)" = 'UTC' ]

# test and make sure DNS works too
RUN cp -L /etc/resolv.conf rootfs/etc/ \
	&& chroot rootfs /bin/sh -xec 'nslookup google.com' \
	&& rm rootfs/etc/resolv.conf
