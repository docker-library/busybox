#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM arm32v7/debian:trixie-slim

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

# grab/use buildroot for its uClibc toolchain

RUN set -eux; \
	apt-get install --update -y \
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
	apt-get dist-clean

RUN set -eux; \
	mkdir -p ~/.gnupg; \
	for key in \
# pub   dsa1024 2009-01-15 [SC]
#       AB07 D806 D2CE 741F B886  EE50 B025 BA8B 59C3 6319
# uid           [ unknown] Peter Korsgaard <jacmet@uclibc.org>
# sub   elg2048 2009-01-15 [E]
		AB07D806D2CE741FB886EE50B025BA8B59C36319 \
# pub   rsa4096 2019-04-26 [SC] [expires: 2032-04-26]
#       18C7 DF28 19C1 733D 822D  599E A500 D6EE 9CB0 E540
# uid           [ unknown] Arnout Vandecappelle <arnout@rnout.be>
# uid           [ unknown] Arnout Vandecappelle <arnout.vandecappelle@essensium.com>
# sub   rsa4096 2019-04-26 [E] [expires: 2032-04-26]
		18C7DF2819C1733D822D599EA500D6EE9CB0E540 \
	; do \
		gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
	done

# https://buildroot.org/download.html
# https://buildroot.org/downloads/?C=M;O=D
ENV BUILDROOT_VERSION 2025.11.1

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
		BR2_TOOLCHAIN_BUILDROOT_GLIBC \
	'; \
	\
# buildroot arches: https://gitlab.com/buildroot.org/buildroot/-/tree/HEAD/arch
# buildroot+uclibc arches: https://gitlab.com/buildroot.org/buildroot/-/blob/HEAD/package/uclibc/Config.in ("config BR2_PACKAGE_UCLIBC_ARCH_SUPPORTS")
	dpkgArch="$(dpkg --print-architecture)"; \
	case "$dpkgArch" in \
# explicitly target amd64 v1
		amd64) \
			setConfs="$setConfs \
				BR2_x86_64=y \
				BR2_x86_x86_64=y \
			"; \
			;; \
			\
		arm64) \
			setConfs="$setConfs \
				BR2_aarch64=y \
			"; \
# https://github.com/docker-library/busybox/issues/149
			setConfs="$setConfs BR2_ARM64_PAGE_SIZE_64K=y"; \
			unsetConfs="$unsetConfs BR2_ARM64_PAGE_SIZE_4K"; \
# (it's reasonable to use a larger page size than the host, but not the reverse, and some distros default to 64k instead of 4k)
			;; \
			\
# https://wiki.debian.org/ArmEabiPort#Choice_of_minimum_CPU
# https://github.com/free-electrons/toolchains-builder/blob/db259641eaf5bbcf13f4a3c5003e5436e806770c/configs/arch/armv5-eabi.config
# https://gitlab.com/buildroot.org/buildroot/-/blob/HEAD/arch/Config.in.arm
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
# https://gitlab.com/buildroot.org/buildroot/-/blob/HEAD/arch/Config.in.arm
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
		CONFIG_STATIC=y \
		\
# https://github.com/docker-library/busybox/issues/232
# https://git.busybox.net/busybox/tree/miscutils/inotifyd.c?id=6937487be73cd4563b876413277a295a5fe2f32c#n31
# "default n  # doesn't build on Knoppix 5" 😅😂
		CONFIG_INOTIFYD=y \
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
# TODO make this create symlinks instead so the output tarball is cleaner (but "-s" outputs absolute symlinks which is kind of annoying to deal with -- we should also consider letting busybox determine the "install paths"; see "busybox --list-full")
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
