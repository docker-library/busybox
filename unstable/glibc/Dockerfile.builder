#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM debian:bullseye-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y \
		bzip2 \
		curl \
		gcc \
		gnupg dirmngr \
		make \
		patch \
	; \
	rm -rf /var/lib/apt/lists/*

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --batch --keyserver keyserver.ubuntu.com --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

ENV BUSYBOX_VERSION 1.35.0
ENV BUSYBOX_SHA256 faeeb244c35a348a334f4a59e44626ee870fb07b6884d68c10ae8bc19f83a694

RUN set -eux; \
	tarball="busybox-${BUSYBOX_VERSION}.tar.bz2"; \
	curl -fL -o busybox.tar.bz2.sig "https://busybox.net/downloads/$tarball.sig"; \
	curl -fL -o busybox.tar.bz2 "https://busybox.net/downloads/$tarball"; \
	echo "$BUSYBOX_SHA256 *busybox.tar.bz2" | sha256sum -c -; \
	gpg --batch --verify busybox.tar.bz2.sig busybox.tar.bz2; \
	mkdir -p /usr/src/busybox; \
	tar -xf busybox.tar.bz2 -C /usr/src/busybox --strip-components 1; \
	rm busybox.tar.bz2*

WORKDIR /usr/src/busybox

RUN set -eux; \
	\
	setConfs=' \
		CONFIG_AR=y \
		CONFIG_FEATURE_AR_CREATE=y \
		CONFIG_FEATURE_AR_LONG_FILENAMES=y \
# CONFIG_LAST_SUPPORTED_WCHAR: see https://github.com/docker-library/busybox/issues/13 (UTF-8 input)
		CONFIG_LAST_SUPPORTED_WCHAR=0 \
# As long as we rely on libnss (see below), we have to have libc.so anyhow, so we've removed CONFIG_STATIC here... :cry:
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
	done

RUN set -eux; \
	nproc="$(nproc)"; \
	make -j "$nproc" busybox; \
	./busybox --help; \
	mkdir -p rootfs/bin; \
	ln -vL busybox rootfs/bin/; \
	\
# copy "getconf" from Debian
	getconf="$(which getconf)"; \
	ln -vL "$getconf" rootfs/bin/getconf; \
	\
# hack hack hack hack hack
# with glibc, busybox (static or not) uses libnss for DNS resolution :(
	mkdir -p rootfs/etc; \
	cp /etc/nsswitch.conf rootfs/etc/; \
	mkdir -p rootfs/lib; \
	ln -sT lib rootfs/lib64; \
	gccMultiarch="$(gcc -print-multiarch)"; \
	set -- \
		rootfs/bin/busybox \
		rootfs/bin/getconf \
		/lib/"$gccMultiarch"/libnss*.so.* \
# libpthread is part of glibc: https://stackoverflow.com/a/11210463/433558
		/lib/"$gccMultiarch"/libpthread*.so.* \
	; \
	while [ "$#" -gt 0 ]; do \
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
		ldd="$(ldd "$f" | awk ' \
			$1 ~ /^\// { print $1; next } \
			$2 == "=>" && $3 ~ /^\// { print $3; next } \
		')"; \
		set -- "$@" $ldd; \
	done; \
	chroot rootfs /bin/getconf _NPROCESSORS_ONLN; \
	\
	chroot rootfs /bin/busybox --install /bin

# install a few extra files from buildroot (/etc/passwd, etc)
RUN set -eux; \
	buildrootVersion='2022.08'; \
	for file in \
		system/device_table.txt \
		system/skeleton/etc/group \
		system/skeleton/etc/passwd \
		system/skeleton/etc/shadow \
	; do \
		dir="$(dirname "$file")"; \
		mkdir -p "../buildroot/$dir"; \
		curl -fL -o "../buildroot/$file" "https://git.busybox.net/buildroot/plain/$file?id=$buildrootVersion"; \
		[ -s "../buildroot/$file" ]; \
	done; \
	\
	mkdir -p rootfs/etc; \
	ln -vL \
		../buildroot/system/skeleton/etc/group \
		../buildroot/system/skeleton/etc/passwd \
		../buildroot/system/skeleton/etc/shadow \
		rootfs/etc/ \
	; \
# CVE-2019-5021, https://github.com/docker-library/official-images/pull/5880#issuecomment-490681907
	grep -E '^root::' rootfs/etc/shadow; \
	sed -ri -e 's/^root::/root:*:/' rootfs/etc/shadow; \
	grep -E '^root:[*]:' rootfs/etc/shadow; \
# set expected permissions, etc too (https://git.busybox.net/buildroot/tree/system/device_table.txt)
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
	' ../buildroot/system/device_table.txt | sh -eux

# create missing home directories
RUN set -eux; \
	cd rootfs; \
	for userHome in $(awk -F ':' '{ print $3 ":" $4 "=" $6 }' etc/passwd); do \
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
RUN set -eux; \
	ln -vL /usr/share/zoneinfo/UTC rootfs/etc/localtime; \
	[ "$(chroot rootfs date +%Z)" = 'UTC' ]

# test and make sure DNS works too
RUN cp -L /etc/resolv.conf rootfs/etc/; \
	chroot rootfs /bin/sh -xec 'nslookup google.com'; \
	rm rootfs/etc/resolv.conf

# vim:set ft=dockerfile:
