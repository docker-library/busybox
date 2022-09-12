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

# grab/use buildroot for its uClibc toolchain

RUN set -eux; \
	apt-get update; \
	apt-get install -y \
		bc \
		cpio \
		dpkg-dev \
		file \
		g++ \
		perl \
		python3 \
		rsync \
		unzip \
		wget \
	; \
	rm -rf /var/lib/apt/lists/*

# pub   1024D/59C36319 2009-01-15
#       Key fingerprint = AB07 D806 D2CE 741F B886  EE50 B025 BA8B 59C3 6319
# uid                  Peter Korsgaard <jacmet@uclibc.org>
# sub   2048g/45428075 2009-01-15
RUN gpg --batch --keyserver keyserver.ubuntu.com --recv-keys AB07D806D2CE741FB886EE50B025BA8B59C36319

# https://buildroot.org/download.html
# https://buildroot.org/downloads/?C=M;O=D
ENV BUILDROOT_VERSION 2022.08

RUN set -eux; \
	tarball="buildroot-${BUILDROOT_VERSION}.tar.xz"; \
	curl -fL -o buildroot.tar.xz "https://buildroot.org/downloads/$tarball"; \
	curl -fL -o buildroot.tar.xz.sign "https://buildroot.org/downloads/$tarball.sign"; \
	gpg --batch --decrypt --output buildroot.tar.xz.txt buildroot.tar.xz.sign; \
	awk '$1 == "SHA1:" && $2 ~ /^[0-9a-f]+$/ && $3 == "'"$tarball"'" { print $2, "*buildroot.tar.xz" }' buildroot.tar.xz.txt > buildroot.tar.xz.sha1; \
	test -s buildroot.tar.xz.sha1; \
	sha1sum -c buildroot.tar.xz.sha1; \
	mkdir -p /usr/src/buildroot; \
	tar -xf buildroot.tar.xz -C /usr/src/buildroot --strip-components 1; \
	rm buildroot.tar.xz*

RUN set -eux; \
	\
	cd /usr/src/buildroot; \
	\
	setConfs=' \
		BR2_STATIC_LIBS=y \
		BR2_TOOLCHAIN_BUILDROOT_UCLIBC=y \
		BR2_TOOLCHAIN_BUILDROOT_WCHAR=y \
	'; \
	\
	unsetConfs=' \
		BR2_SHARED_LIBS \
	'; \
	\
# buildroot arches: https://git.busybox.net/buildroot/tree/arch
# buildroot+uclibc arches: https://git.busybox.net/buildroot/tree/package/uclibc/Config.in ("config BR2_PACKAGE_UCLIBC_ARCH_SUPPORTS")
	dpkgArch="$(dpkg --print-architecture)"; \
	case "$dpkgArch" in \
		amd64) \
			setConfs="$setConfs \
				BR2_x86_64=y \
			"; \
			;; \
			\
		arm64) \
			setConfs="$setConfs \
				BR2_aarch64=y \
			"; \
			;; \
			\
# https://wiki.debian.org/ArmEabiPort#Choice_of_minimum_CPU
# https://github.com/free-electrons/toolchains-builder/blob/db259641eaf5bbcf13f4a3c5003e5436e806770c/configs/arch/armv5-eabi.config
# https://git.busybox.net/buildroot/tree/arch/Config.in.arm
# (Debian minimums at ARMv4, we minimum at ARMv5 instead)
		armel) \
			setConfs="$setConfs \
				BR2_arm=y \
				BR2_arm926t=y \
				BR2_ARM_EABI=y \
				BR2_ARM_INSTRUCTIONS_THUMB=y \
				BR2_ARM_SOFT_FLOAT=y \
			"; \
			;; \
			\
# "Currently the Debian armhf port requires at least an ARMv7 CPU with Thumb-2 and VFP3D16."
# https://wiki.debian.org/ArmHardFloatPort#Supported_devices
# https://github.com/free-electrons/toolchains-builder/blob/db259641eaf5bbcf13f4a3c5003e5436e806770c/configs/arch/armv7-eabihf.config
# https://git.busybox.net/buildroot/tree/arch/Config.in.arm
		armhf) \
			setConfs="$setConfs \
				BR2_arm=y \
				BR2_cortex_a9=y \
				BR2_ARM_EABIHF=y \
				BR2_ARM_ENABLE_VFP=y \
				BR2_ARM_FPU_VFPV3D16=y \
				BR2_ARM_INSTRUCTIONS_THUMB2=y \
			"; \
			unsetConfs="$unsetConfs BR2_ARM_SOFT_FLOAT"; \
			;; \
			\
		i386) \
			setConfs="$setConfs \
				BR2_i386=y \
			"; \
			;; \
			\
		mips64el) \
			setConfs="$setConfs \
				BR2_mips64el=y \
				BR2_mips_64r2=y \
				BR2_MIPS_NABI64=y \
			"; \
			unsetConfs="$unsetConfs \
				BR2_MIPS_SOFT_FLOAT \
			"; \
			;; \
			\
# TODO ppc64el ? (needs BR2_TOOLCHAIN_BUILDROOT_UCLIBC support)
			\
		riscv64) \
			setConfs="$setConfs \
				BR2_riscv=y \
				BR2_RISCV_64=y \
			"; \
			;; \
			\
# TODO s390x ? (needs BR2_TOOLCHAIN_BUILDROOT_UCLIBC support)
			\
		*) \
			echo >&2 "error: unsupported architecture '$dpkgArch'!"; \
			exit 1; \
			;; \
	esac; \
	if [ "$dpkgArch" != 'i386' ]; then \
		unsetConfs="$unsetConfs BR2_i386"; \
	fi; \
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

# https://www.finnie.org/2014/02/13/compiling-busybox-with-uclibc/
RUN set -eux; \
# force a particular GNU arch for "host-gmp" (otherwise it fails on some arches)
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	make -C /usr/src/buildroot \
		HOST_GMP_CONF_OPTS="--build='"$gnuArch"'" \
# building host-tar:
#   configure: error: you should not run configure as root (set FORCE_UNSAFE_CONFIGURE=1 in environment to bypass this check)
		FORCE_UNSAFE_CONFIGURE=1 \
		-j "$(nproc)" \
		toolchain
ENV PATH /usr/src/buildroot/output/host/usr/bin:$PATH

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --batch --keyserver keyserver.ubuntu.com --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

ENV BUSYBOX_VERSION 1.34.1
ENV BUSYBOX_SHA256 415fbd89e5344c96acf449d94a6f956dbed62e18e835fc83e064db33a34bd549

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
		CONFIG_STATIC=y \
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
	CROSS_COMPILE="$(basename /usr/src/buildroot/output/host/usr/*-buildroot-linux-uclibc*)"; \
	export CROSS_COMPILE="$CROSS_COMPILE-"; \
	make -j "$nproc" busybox; \
	./busybox --help; \
	mkdir -p rootfs/bin; \
	ln -vL busybox rootfs/bin/; \
	\
# copy "getconf" from buildroot
	ln -vL ../buildroot/output/target/usr/bin/getconf rootfs/bin/; \
	chroot rootfs /bin/getconf _NPROCESSORS_ONLN; \
	\
	chroot rootfs /bin/busybox --install /bin

# install a few extra files from buildroot (/etc/passwd, etc)
RUN set -eux; \
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
