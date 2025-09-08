#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM riscv64/debian:trixie-slim

RUN set -eux; \
	apt-get install --update -y \
		bzip2 \
		curl \
		gcc \
		gnupg \
		make \
		patch \
	; \
	apt-get dist-clean

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN mkdir -p ~/.gnupg && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

# https://busybox.net: 19 May 2023
ENV BUSYBOX_VERSION 1.36.1
ENV BUSYBOX_SHA256 b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314

RUN set -eux; \
	tarball="busybox-${BUSYBOX_VERSION}.tar.bz2"; \
	curl -fL -o busybox.tar.bz2.sig "https://busybox.net/downloads/$tarball.sig"; \
	curl -fL -o busybox.tar.bz2 "https://busybox.net/downloads/$tarball"; \
	echo "$BUSYBOX_SHA256 *busybox.tar.bz2" | sha256sum -c -; \
	gpg --batch --verify busybox.tar.bz2.sig busybox.tar.bz2; \
# Alpine... 😅
	mkdir -p /usr/src; \
	tar -xf busybox.tar.bz2 -C /usr/src "busybox-$BUSYBOX_VERSION"; \
	mv "/usr/src/busybox-$BUSYBOX_VERSION" /usr/src/busybox; \
	rm busybox.tar.bz2*; \
	\
# save the tarball's filesystem timestamp persistently (in case building busybox modifies it) so we can use it for reproducible rootfs later
	SOURCE_DATE_EPOCH="$(stat -c '%Y' /usr/src/busybox | tee /usr/src/busybox.SOURCE_DATE_EPOCH)"; \
	date="$(date -d "@$SOURCE_DATE_EPOCH" '+%Y%m%d%H%M.%S')"; \
	touch -t "$date" /usr/src/busybox.SOURCE_DATE_EPOCH; \
# for logging validation/edification
	date --date "@$SOURCE_DATE_EPOCH" --rfc-2822

WORKDIR /usr/src/busybox

# apply necessary/minimal patches (see /.patches/ in the top level of the repository)
COPY \
	/.patches/no-cbq.patch \
	./.patches/
RUN set -eux; \
	for patch in .patches/*.patch; do \
		patch -p1 --input="$patch"; \
	done; \
	rm -rf .patches

RUN set -eux; \
	\
# build date/time gets embedded in the BusyBox binary -- SOURCE_DATE_EPOCH should override that
	SOURCE_DATE_EPOCH="$(cat /usr/src/busybox.SOURCE_DATE_EPOCH)"; \
	export SOURCE_DATE_EPOCH; \
# (has to be set in the config stage for making sure "AUTOCONF_TIMESTAMP" is embedded correctly)
	\
	setConfs=' \
		CONFIG_AR=y \
		CONFIG_FEATURE_AR_CREATE=y \
		CONFIG_FEATURE_AR_LONG_FILENAMES=y \
# CONFIG_LAST_SUPPORTED_WCHAR: see https://github.com/docker-library/busybox/issues/13 (UTF-8 input)
		CONFIG_LAST_SUPPORTED_WCHAR=0 \
# As long as we rely on libnss (see below), we have to have libc.so anyhow, so we've removed CONFIG_STATIC here... 😭
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
# https://git.busybox.net/busybox/tree/Makefile?h=1_37_stable#n145
# we need to override SUBARCH explicitly (via ARCH) to avoid "uname -m" which gives the wrong answer for builds like i386 on an amd64 machine because kernel architecture != userspace architecture
# see https://git.busybox.net/busybox/tree/arch?h=1_37_stable#n145 for the only important values this *has* to match (everything else is best-effort, and needs to match the munging in https://git.busybox.net/busybox/tree/Makefile?h=1_37_stable#n185)
	distroArch="$(dpkg --print-architecture)"; \
	case "$distroArch" in \
		amd64 | x86_64)        ARCH='x86_64'  ;; \
		arm64 | aarch64)       ARCH='aarch64' ;; \
		armhf | armel | armv*) ARCH='arm'     ;; \
		i386  | x86)           ARCH='i386'    ;; \
		mips*)                 ARCH='mips'    ;; \
		ppc*)                  ARCH='powerpc' ;; \
		riscv64)               ARCH='riscv64' ;; \
		s390x)                 ARCH='s390'    ;; \
		*) echo >&2 "error: unknown architecture: '$distroArch'"; exit 1 ;; \
	esac; \
	[ -n "$ARCH" ]; \
	export ARCH; \
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
# TODO make this create symlinks instead so the output tarball is cleaner (but "-s" outputs absolute symlinks which is kind of annoying to deal with -- we should also consider letting busybox determine the "install paths"; see "busybox --list-full")
	chroot rootfs /bin/busybox --install /bin

# install a few extra files from buildroot (/etc/passwd, etc)
RUN set -eux; \
	buildrootVersion='2025.08'; \
	for file in \
		system/device_table.txt \
		system/skeleton/etc/group \
		system/skeleton/etc/passwd \
		system/skeleton/etc/shadow \
	; do \
		dir="$(dirname "$file")"; \
		mkdir -p "../buildroot/$dir"; \
		curl -fL -o "../buildroot/$file" "https://gitlab.com/buildroot.org/buildroot/-/raw/$buildrootVersion/$file"; \
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
# set expected permissions, etc too (https://gitlab.com/buildroot.org/buildroot/-/blob/HEAD/system/device_table.txt)
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

# create missing home directories and ensure /usr/bin/env exists
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
	done; \
	if [ ! -s usr/bin/env ] && [ -s bin/env ]; then \
		mkdir -p usr/bin; \
		ln -s ../../bin/env usr/bin/; \
	fi

# test and make sure it works
RUN chroot rootfs /usr/bin/env sh -xec 'true'

# ensure correct timezone (UTC)
RUN set -eux; \
	ln -vL /usr/share/zoneinfo/UTC rootfs/etc/localtime; \
	[ "$(chroot rootfs date +%Z)" = 'UTC' ]

# test and make sure DNS works too
RUN set -eux; \
	cp -L /etc/resolv.conf rootfs/etc/; \
	chroot rootfs /bin/sh -xec 'nslookup google.com'; \
	rm rootfs/etc/resolv.conf

# vim:set ft=dockerfile:
