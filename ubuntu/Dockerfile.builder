FROM ubuntu:trusty

ENV BUSYBOX_VERSION 1:1.21.0-1ubuntu1

RUN apt-get update && apt-get install -y --no-install-recommends \
		busybox-static=$BUSYBOX_VERSION \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /rootfs

# create /tmp
RUN mkdir -p tmp \
	&& chmod 1777 tmp

RUN mkdir -p etc root \
	&& echo root:*:0:0:root:/root:/bin/sh > etc/passwd \
	&& echo root::0: > etc/group

RUN mkdir -p bin \
	&& ln -v /bin/busybox bin/ \
	&& chroot . /bin/busybox --install -s /bin

# test and make sure it works
RUN chroot . /bin/sh -xec 'true'

# hack hack hack hack hack
# with glibc, static busybox uses libnss for DNS resolution :(
RUN set -ex \
	&& cp /etc/nsswitch.conf etc/ \
	&& mkdir -p lib \
	&& set -- /lib/*-linux-gnu/libnss*.so.* \
	&& while [ "$#" -gt 0 ]; do \
		f="$1"; shift; \
		fn="$(basename "$f")"; \
		if [ -e "lib/$fn" ]; then continue; fi; \
		ln -L "$f" "lib/$fn"; \
		set -- "$@" $(ldd "$f" | awk ' \
			$1 ~ /^\// { print $1; next } \
			$2 == "=>" && $3 ~ /^\// { print $3; next } \
		'); \
	done

# test and make sure DNS works too
RUN cp -L /etc/resolv.conf etc/ \
	&& chroot . /bin/sh -xec 'nslookup google.com' \
	&& rm etc/resolv.conf
