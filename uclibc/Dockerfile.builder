FROM debian:stretch-slim

RUN apt-get update && apt-get install -y \
		bzip2 \
		curl \
		gcc \
		gnupg dirmngr \
		make \
		\
# buildroot
		bc \
		cpio \
		dpkg-dev \
		g++ \
		patch \
		perl \
		python \
		rsync \
		unzip \
		wget \
	&& rm -rf /var/lib/apt/lists/*

# we grab buildroot for it's uClibc toolchain

# pub   1024D/59C36319 2009-01-15
#       Key fingerprint = AB07 D806 D2CE 741F B886  EE50 B025 BA8B 59C3 6319
# uid                  Peter Korsgaard <jacmet@uclibc.org>
# sub   2048g/45428075 2009-01-15
RUN gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys AB07D806D2CE741FB886EE50B025BA8B59C36319

# https://buildroot.org/download.html
# https://buildroot.org/downloads/?C=M;O=D
ENV BUILDROOT_VERSION 2019.05

RUN set -ex; \
	tarball="buildroot-${BUILDROOT_VERSION}.tar.bz2"; \
	curl -fL -o buildroot.tar.bz2 "https://buildroot.org/downloads/$tarball"; \
	curl -fL -o buildroot.tar.bz2.sign "https://buildroot.org/downloads/$tarball.sign"; \
	gpg --batch --decrypt --output buildroot.tar.bz2.txt buildroot.tar.bz2.sign; \
	awk '$1 == "SHA1:" && $2 ~ /^[0-9a-f]+$/ && $3 == "'"$tarball"'" { print $2, "*buildroot.tar.bz2" }' buildroot.tar.bz2.txt > buildroot.tar.bz2.sha1; \
	test -s buildroot.tar.bz2.sha1; \
	sha1sum -c buildroot.tar.bz2.sha1; \
	mkdir -p /usr/src/buildroot; \
	tar -xf buildroot.tar.bz2 -C /usr/src/buildroot --strip-components 1; \
	rm buildroot.tar.bz2*

RUN set -ex; \
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
# buildroot+uclibc arches: https://git.busybox.net/buildroot/tree/toolchain/toolchain-buildroot/Config.in ("config BR2_TOOLCHAIN_BUILDROOT_UCLIBC")
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
# TODO ppc64el ? (needs BR2_TOOLCHAIN_BUILDROOT_UCLIBC support)
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

# http://www.finnie.org/2014/02/13/compiling-busybox-with-uclibc/
RUN set -ex; \
# force a particular GNU arch for "host-gmp" (otherwise it fails on some arches)
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	make -C /usr/src/buildroot HOST_GMP_CONF_OPTS="--build='"$gnuArch"'" -j "$(nproc)" toolchain
ENV PATH /usr/src/buildroot/output/host/usr/bin:$PATH

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

ENV BUSYBOX_VERSION 1.31.0

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
RUN set -ex; \
	\
	setConfs=' \
		CONFIG_AR=y \
		CONFIG_FEATURE_AR_CREATE=y \
		CONFIG_FEATURE_AR_LONG_FILENAMES=y \
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
	done;

RUN set -ex \
	&& make -j "$(nproc)" \
		CROSS_COMPILE="$(basename /usr/src/buildroot/output/host/usr/*-buildroot-linux-uclibc*)-" \
		busybox \
	&& ./busybox --help \
	&& mkdir -p rootfs/bin \
	&& ln -vL busybox rootfs/bin/ \
	\
	&& ln -vL ../buildroot/output/target/usr/bin/getconf rootfs/bin/ \
	\
	&& chroot rootfs /bin/getconf _NPROCESSORS_ONLN \
	\
	&& chroot rootfs /bin/busybox --install /bin

# install a few extra files from buildroot (/etc/passwd, etc)
RUN set -ex; \
	mkdir -p rootfs/etc; \
	for f in passwd shadow group; do \
		ln -vL \
			"../buildroot/system/skeleton/etc/$f" \
			"rootfs/etc/$f"; \
	done; \
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
	' ../buildroot/system/device_table.txt | bash -Eeuo pipefail -x

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
