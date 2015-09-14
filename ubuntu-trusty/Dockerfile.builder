FROM ubuntu:trusty

ENV BUSYBOX_STATIC_VERSION 1:1.21.0-1ubuntu1

RUN apt-get update && apt-get install -y --no-install-recommends \
		busybox-static=$BUSYBOX_STATIC_VERSION \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /rootfs
RUN mkdir bin etc lib tmp \
	&& ln -s lib lib64 \
	&& ln -s bin sbin

RUN cp /etc/nsswitch.conf etc/

RUN echo root:*:0:0:root:/:/bin/sh > etc/passwd
RUN echo root::0: > etc/group

RUN /bin/busybox --install -s bin/ \
	&& cp /bin/busybox bin/

RUN bash -c 'cp /lib/x86_64-linux-gnu/lib{c,m,dl,rt,nsl,nss_*,pthread,resolv}.so.* /lib/x86_64-linux-gnu/ld-linux-x86-64.so.* lib/'

# test and make sure it works
RUN chroot . /bin/sh -xec 'true'
