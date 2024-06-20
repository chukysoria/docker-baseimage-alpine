# syntax=docker/dockerfile:1

ARG BUILD_FROM=alpine:3.20.1

FROM ${BUILD_FROM} as rootfs-stage

ARG BUILD_ARCH=x86_64
ARG BUILD_EXT_RELEASE=3.20

# environment
ENV ROOTFS=/root-out
ENV REL=v${BUILD_EXT_RELEASE}
ENV MIRROR=http://dl-cdn.alpinelinux.org/alpine
ENV PACKAGES=\
alpine-baselayout=3.6.5-r0,\
alpine-keys=2.4-r1,\
apk-tools=2.14.4-r0,\
busybox=1.36.1-r29,\
musl-utils=1.2.5-r0

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
ARG S6_OVERLAY_VERSION="3.2.0.0"

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

ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"

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
    alpine-release=3.20.1-r0 \
    bash=5.2.26-r0 \
    ca-certificates=20240226-r0 \
    catatonit=0.2.0-r0 \
    coreutils=9.5-r1 \
    curl=8.7.1-r0 \
    findutils=4.9.0-r5 \
    jq=1.7.1-r0 \
    netcat-openbsd=1.226-r0 \
    procps-ng=4.0.4-r0 \
    shadow=4.15.1-r0 \
    tzdata=2024a-r1 \
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
