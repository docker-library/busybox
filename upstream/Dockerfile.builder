FROM debian:jessie

RUN apt-get update && apt-get install -y \
		bzip2 \
		curl \
		gcc \
		make \
		\
# buildroot
		bc \
		cpio \
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
RUN gpg --keyserver ha.pool.sks-keyservers.net --recv-keys AB07D806D2CE741FB886EE50B025BA8B59C36319

ENV BUILDROOT_VERSION 2015.08.1

RUN set -x \
	&& mkdir -p /usr/src/buildroot \
	&& cd /usr/src/buildroot \
	&& curl -fsSL "http://buildroot.uclibc.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz" -o buildroot.tar.bz2 \
	&& curl -fsSL "http://buildroot.uclibc.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz.sign" -o buildroot.tar.bz2.sign \
	&& gpg --verify buildroot.tar.bz2.sign \
	&& tar -xf buildroot.tar.bz2 --strip-components 1 \
	&& rm buildroot.tar.bz2*

RUN yConfs=' \
		BR2_STATIC_LIBS \
		BR2_TOOLCHAIN_BUILDROOT_INET_RPC \
		BR2_TOOLCHAIN_BUILDROOT_WCHAR \
		BR2_x86_64 \
	' \
	&& nConfs=' \
		BR2_SHARED_LIBS \
		BR2_i386 \
	' \
	&& set -xe \
	&& cd /usr/src/buildroot \
	&& make defconfig \
	&& for conf in $nConfs; do \
		sed -i "s!^$conf=y!# $conf is not set!" .config; \
	done \
	&& for conf in $yConfs; do \
		sed -i "s!^# $conf is not set\$!$conf=y!" .config; \
		grep -q "^$conf=y" .config || echo "$conf=y" >> .config; \
	done \
	&& make oldconfig \
	&& for conf in $nConfs; do \
		! grep -q "^$conf=y" .config; \
	done \
	&& for conf in $yConfs; do \
		grep -q "^$conf=y" .config; \
	done

# http://www.finnie.org/2014/02/13/compiling-busybox-with-uclibc/
RUN make -C /usr/src/buildroot -j$(nproc) toolchain
ENV PATH /usr/src/buildroot/output/host/usr/bin:$PATH

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

WORKDIR /usr/src/busybox

ENV BUSYBOX_VERSION 1.24.0

RUN set -x \
	&& curl -fsSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2" -o busybox.tar.bz2 \
	&& curl -fsSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2.sign" -o busybox.tar.bz2.sign \
	&& gpg --verify busybox.tar.bz2.sign \
	&& tar -xf busybox.tar.bz2 --strip-components 1 \
	&& rm busybox.tar.bz2*

RUN confs=' \
		CONFIG_AR \
		CONFIG_FEATURE_AR_LONG_FILENAMES \
		CONFIG_FEATURE_AR_CREATE \
		CONFIG_STATIC \
	' \
	&& set -xe \
	&& make defconfig \
	&& for conf in $confs; do \
		sed -i "s!^# $conf is not set\$!$conf=y!" .config; \
		grep -q "^$conf=y" .config || echo "$conf=y" >> .config; \
	done \
	&& make oldconfig \
	&& for conf in $confs; do \
		grep -q "^$conf=y" .config; \
	done

RUN set -x \
	&& make -j$(nproc) \
		CROSS_COMPILE="$(basename /usr/src/buildroot/output/host/usr/*-buildroot-linux-uclibc)-" \
		busybox \
	&& mkdir -p rootfs/bin \
	&& ln -v busybox rootfs/bin/ \
	&& rootfs/bin/busybox --install rootfs/bin \
	&& ln -v ../buildroot/output/target/usr/bin/getconf rootfs/bin/

RUN mkdir -p rootfs/etc \
	&& ln -v \
		/usr/src/buildroot/system/skeleton/etc/passwd \
		/usr/src/buildroot/system/skeleton/etc/shadow \
		/usr/src/buildroot/system/skeleton/etc/group \
		rootfs/etc/

# create /tmp
RUN mkdir -p rootfs/tmp \
	&& chmod 1777 rootfs/tmp

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
		fi; \
	done
