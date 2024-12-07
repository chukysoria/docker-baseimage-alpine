# syntax=docker/dockerfile:1@sha256:db1ff77fb637a5955317c7a3a62540196396d565f3dd5742e76dddbb6d75c4c5

ARG BUILD_FROM=alpine:3.21.0@sha256:21dc6063fd678b478f57c0e13f47560d0ea4eeba26dfc947b2a4f81f686b9f45
FROM ${BUILD_FROM} AS rootfs-stage

ARG BUILD_ARCH=x86_64
ARG BUILD_EXT_RELEASE=3.21

# environment
ENV ROOTFS=/root-out
ENV REL=v${BUILD_EXT_RELEASE}
ENV MIRROR=http://dl-cdn.alpinelinux.org/alpine
ENV PACKAGES=\
alpine-baselayout=3.6.8-r0,\
alpine-keys=2.5-r0,\
apk-tools=2.14.6-r2,\
busybox=1.37.0-r8,\
musl-utils=1.2.5-r8

# install packages
RUN \
  apk add --no-cache \
    bash \
    curl \
    xz

# build rootfs
RUN <<EOF
  mkdir -p "$ROOTFS/etc/apk" &&
  {
    echo "$MIRROR/$REL/main";
    echo "$MIRROR/$REL/community";
  } > "$ROOTFS/etc/apk/repositories" &&
  apk --root "$ROOTFS" --no-cache --keys-dir /etc/apk/keys add --arch $BUILD_ARCH --initdb ${PACKAGES//,/ } &&
  sed -i -e 's/^root::/root:!:/' /root-out/etc/shadow
EOF

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.2.0.2"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
RUN <<EOF
  if [[ $BUILD_ARCH == "armv7" ]]; then
    S6_OVERLAY_ARCH=armhf
  else
    S6_OVERLAY_ARCH=$BUILD_ARCH
  fi
  curl -L -o /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz
  tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz
EOF

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

# Runtime stage
FROM scratch
COPY --from=rootfs-stage /root-out/ /
ARG BUILD_DATE
ARG BUILD_VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
LABEL build_version="Chukyserver.io version:- ${BUILD_VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="chukysoria"

ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
  HOME="/root" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    alpine-release=3.21.0-r0 \
    bash=5.2.37-r0 \
    ca-certificates=20241010-r0 \
    catatonit=0.2.0-r0 \
    coreutils=9.5-r1 \
		curl=8.11.0-r2 \
    findutils=4.10.0-r0 \
    jq=1.7.1-r0 \
    netcat-openbsd=1.226.1.1-r0 \
    procps-ng=4.0.4-r2 \
    shadow=4.16.0-r1 \
    tzdata=2024b-r1 \
  && \
  echo "**** create abc user and make our folders ****" && \
  groupmod -g 1000 users && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /app \
    /config \
    /defaults \
    /lsiopy && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
