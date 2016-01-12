FROM debian:jessie

RUN apt-get update && apt-get install -y \
		bzip2 \
		curl \
		gcc \
		make \
	&& rm -rf /var/lib/apt/lists/*

# pub   1024D/ACC9965B 2006-12-12
#       Key fingerprint = C9E9 416F 76E6 10DB D09D  040F 47B7 0C55 ACC9 965B
# uid                  Denis Vlasenko <vda.linux@googlemail.com>
# sub   1024g/2C766641 2006-12-12
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

ENV BUSYBOX_VERSION 1.24.1

RUN set -x \
	&& curl -fsSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2" -o busybox.tar.bz2 \
	&& curl -fsSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2.sign" -o busybox.tar.bz2.sign \
	&& gpg --verify busybox.tar.bz2.sign \
	&& tar -xjf busybox.tar.bz2 \
	&& mkdir -p /usr/src \
	&& mv "busybox-${BUSYBOX_VERSION}" /usr/src/busybox \
	&& rm busybox.tar.bz2*

WORKDIR /usr/src/busybox

# TODO remove CONFIG_FEATURE_SYNC_FANCY from this explicit list after the next release of busybox (since it's disabled by default upstream now)
# As long as we rely on libnss, we have to have libc.so anyhow, so
# we've removed CONFIG_STATIC here for now... :cry:
RUN yConfs=' \
		CONFIG_AR \
		CONFIG_FEATURE_AR_LONG_FILENAMES \
		CONFIG_FEATURE_AR_CREATE \
	' \
	&& nConfs=' \
		CONFIG_FEATURE_SYNC_FANCY \
	' \
	&& set -xe \
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

# hack hack hack hack hack
# with glibc, static busybox uses libnss for DNS resolution :(
RUN set -x \
	&& make -j$(nproc) \
		busybox \
	&& ./busybox --help \
	&& mkdir -p rootfs/bin \
	&& ln -vL busybox rootfs/bin/ \
	\
	&& ln -vL "$(which getconf)" rootfs/bin/getconf \
	&& mkdir -p rootfs/etc \
	&& cp /etc/nsswitch.conf rootfs/etc/ \
	&& mkdir -p rootfs/lib \
	&& ln -sT lib rootfs/lib64 \
	&& set -- \
		rootfs/bin/busybox \
		rootfs/bin/getconf \
		/lib/"$(gcc -print-multiarch)"/libnss*.so.* \
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
	&& chroot rootfs /bin/getconf _NPROCESSORS_ONLN \
	\
	&& chroot rootfs /bin/busybox --install /bin

RUN set -ex \
	&& buildrootVersion='2015.11.1' \
	&& mkdir -p rootfs/etc \
	&& for f in passwd shadow group; do \
		curl -fSL \
			"http://git.busybox.net/buildroot/plain/system/skeleton/etc/$f?id=$buildrootVersion" \
			-o "rootfs/etc/$f"; \
	done

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

# test and make sure it works
RUN chroot rootfs /bin/sh -xec 'true'

# ensure correct timezone (UTC)
RUN ln -v /etc/localtime rootfs/etc/ \
	&& [ "$(chroot rootfs date +%Z)" = 'UTC' ]

# test and make sure DNS works too
RUN cp -L /etc/resolv.conf rootfs/etc/ \
	&& chroot rootfs /bin/sh -xec 'nslookup google.com' \
	&& rm rootfs/etc/resolv.conf
