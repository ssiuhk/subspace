FROM golang:1.14 as build

RUN apt-get update \
    && apt-get install -y git make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

COPY Makefile ./
# go.mod and go.sum if exists
COPY go.* ./
COPY *.go ./
COPY static ./static
COPY templates ./templates
COPY email ./email

ARG BUILD_VERSION=unknown

ENV GODEBUG="netdns=go http2server=0"

RUN make BUILD_VERSION=${BUILD_VERSION}

FROM alpine:3.11.6
LABEL maintainer="github.com/subspacecommunity/subspace"

COPY --from=build  /src/subspace-linux-amd64 /usr/bin/subspace
COPY bin/my_init /sbin/my_init

ENV DEBIAN_FRONTEND noninteractive


RUN apk add --no-cache \
    iproute2 \
    iptables \ 
    ip6tables \
    dnsmasq \
    socat \
    wget \
    curl \
    python3 \
    libc6-compat \
    wireguard-tools \
    runit \
    tini \
    dpkg

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/bin/subspace /usr/local/bin/entrypoint.sh /sbin/my_init && \
    wget -O /tmp/cloudflared-stable-linux-amd64.deb https://bin.equinox.io/c/VdrWdbjqyF/cloudflared-stable-linux-amd64.deb 2>/dev/null && \
    dpkg --add-architecture amd64 && \
    dpkg -i /tmp/cloudflared-stable-linux-amd64.deb

ENTRYPOINT [ "/sbin/tini", "/usr/local/bin/entrypoint.sh" ]

CMD [ "/sbin/my_init" ]
