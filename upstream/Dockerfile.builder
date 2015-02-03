FROM debian:jessie

RUN apt-get update && apt-get install -y \
		bzip2 \
		curl \
		gcc \
		make \
	&& rm -rf /var/lib/apt/lists/*

RUN gpg --keyserver pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B

WORKDIR /usr/src/busybox

ENV BUSYBOX_VERSION 1.23.1

RUN set -x \
	&& curl -sSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2" -o busybox.tar.bz2 \
	&& curl -sSL "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2.sign" -o busybox.tar.bz2.sign \
	&& gpg --verify busybox.tar.bz2.sign \
	&& tar -xf busybox.tar.bz2 --strip-components 1 \
	&& rm busybox.tar.bz2*

RUN set -x \
	&& make defconfig \
	&& echo 'CONFIG_STATIC=y' >> .config

RUN set -x \
	&& make -j$(nproc) \
	&& mkdir -p rootfs-bin \
	&& ln busybox rootfs-bin/ \
	&& rootfs-bin/busybox --install rootfs-bin

CMD ["./busybox"]
