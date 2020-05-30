#!/usr/bin/env sh
set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

# Require environment variables.
if [ -z "${SUBSPACE_HTTP_HOST-}" ]; then
  echo "Environment variable SUBSPACE_HTTP_HOST required. Exiting."
  exit 1
fi
# Optional environment variables.
if [ -z "${SUBSPACE_BACKLINK-}" ]; then
  export SUBSPACE_BACKLINK=""
fi

if [ -z "${SUBSPACE_IPV4_POOL-}" ]; then
  export SUBSPACE_IPV4_POOL="10.99.97.0/24"
fi
if [ -z "${SUBSPACE_IPV6_POOL-}" ]; then
  export SUBSPACE_IPV6_POOL="fd00::10:97:0/112"
fi
if [ -z "${SUBSPACE_NAMESERVER-}" ]; then
  export SUBSPACE_NAMESERVER="1.1.1.1"
fi

if [ -z "${SUBSPACE_DNS_RESOLVER-}" ]; then
  export SUBSPACE_DNS_RESOLVER="DNSMASQ"
fi

if [ -z "${SUBSPACE_LETSENCRYPT-}" ]; then
  export SUBSPACE_LETSENCRYPT="true"
fi

if [ -z "${SUBSPACE_HTTP_ADDR-}" ]; then
  export SUBSPACE_HTTP_ADDR=":80"
fi

if [ -z "${SUBSPACE_LISTENPORT-}" ]; then
  export SUBSPACE_LISTENPORT="51820"
fi

if [ -z "${SUBSPACE_HTTP_INSECURE-}" ]; then
  export SUBSPACE_HTTP_INSECURE="false"
fi

export DEBIAN_FRONTEND="noninteractive"

if [ -z "${SUBSPACE_IPV4_GW-}" ]; then
  export SUBSPACE_IPV4_PREF=$(echo ${SUBSPACE_IPV4_POOL-} | cut -d '/' -f1 | sed 's/.0$/./g')
  export SUBSPACE_IPV4_GW=$(echo ${SUBSPACE_IPV4_PREF-}1)

fi
if [ -z "${SUBSPACE_IPV6_GW-}" ]; then
  export SUBSPACE_IPV6_PREF=$(echo ${SUBSPACE_IPV6_POOL-} | cut -d '/' -f1 | sed 's/:0$/:/g')
  export SUBSPACE_IPV6_GW=$(echo ${SUBSPACE_IPV6_PREF-}1)
fi

if [ -z "${SUBSPACE_IPV6_NAT_ENABLED-}" ]; then
  export SUBSPACE_IPV6_NAT_ENABLED=1
fi

# Set DNS server
echo "nameserver ${SUBSPACE_NAMESERVER}" >/etc/resolv.conf

#
# WireGuard (${SUBSPACE_IPV4_POOL})
#
if ! test -d /data/wireguard; then
  mkdir /data/wireguard
  cd /data/wireguard

  mkdir clients
  touch clients/null.conf # So you can cat *.conf safely
  mkdir peers
  touch peers/null.conf # So you can cat *.conf safely
  mkdir preSharedKey
  touch preSharedKey/null.psk
  chmod 0700 clients peers preSharedKey

  # Generate public/private server keys.
  wg genkey | tee server.private | wg pubkey >server.public
fi

cat <<WGSERVER >/data/wireguard/server.conf
[Interface]
PrivateKey = $(cat /data/wireguard/server.private)
ListenPort = ${SUBSPACE_LISTENPORT}

WGSERVER
cat /data/wireguard/peers/*.conf >>/data/wireguard/server.conf

if ip link show wg0 2>/dev/null; then
  ip link del wg0
fi
ip link add wg0 type wireguard
export SUBSPACE_IPV4_CIDR=$(echo ${SUBSPACE_IPV4_POOL-} | cut -d '/' -f2)
ip addr add ${SUBSPACE_IPV4_GW}/${SUBSPACE_IPV4_CIDR} dev wg0
export SUBSPACE_IPV6_CIDR=$(echo ${SUBSPACE_IPV6_POOL-} | cut -d '/' -f2)
ip addr add ${SUBSPACE_IPV6_GW}/${SUBSPACE_IPV6_CIDR} dev wg0
wg setconf wg0 /data/wireguard/server.conf
ip link set wg0 up

# dns service
if [ "${SUBSPACE_DNS_RESOLVER}" == "DNSMASQ" ]; then
  if ! test -d /etc/service/dnsmasq; then
    cat <<DNSMASQ >/etc/dnsmasq.conf
      # Only listen on necessary addresses.
      listen-address=127.0.0.1,${SUBSPACE_IPV4_GW},${SUBSPACE_IPV6_GW}

      # Never forward plain names (without a dot or domain part)
      domain-needed

      # Never forward addresses in the non-routed address spaces.
      bogus-priv
DNSMASQ

    mkdir -p /etc/service/dnsmasq
    cat <<RUNIT >/etc/service/dnsmasq/run
#!/bin/sh
exec /usr/sbin/dnsmasq --no-daemon
RUNIT
    chmod +x /etc/service/dnsmasq/run

    # dnsmasq service log
    mkdir -p /etc/service/dnsmasq/log
    mkdir -p /etc/service/dnsmasq/log/main
    cat <<RUNIT >/etc/service/dnsmasq/log/run
#!/bin/sh
exec svlogd -tt ./main
RUNIT
    chmod +x /etc/service/dnsmasq/log/run
  fi

elif [ "${SUBSPACE_DNS_RESOLVER}" == "CLOUDFLARED" ]; then

  # Cloudflared
  if [ -x /usr/local/bin/cloudflared ]; then
      mkdir -p /etc/cloudflared
      touch /etc/cloudflared/cert.pem
      cat << CLOUDFLAREDCFG > /etc/cloudflared/config.yml
proxy-dns: true
address: ${SUBSPACE_IPV4_GW}
proxy-dns-upstream:
 - https://dns.google/dns-query
 - https://1.1.1.1/dns-query
 - https://1.0.0.1/dns-query
CLOUDFLAREDCFG

      mkdir -p /etc/service/cloudflared
      cat <<RUNIT >/etc/service/cloudflared/run
#!/bin/bash
export TUNNEL_DNS_ADDRESS=${SUBSPACE_IPV4_GW}
exec /usr/local/bin/cloudflared --config /etc/cloudflared/config.yml --origincert /etc/cloudflared/cert.pem --no-autoupdate proxy-dns --address ${SUBSPACE_IPV4_GW}
RUNIT
      chmod +x /etc/service/cloudflared/run

      # cloudflared service log
      mkdir -p /etc/service/cloudflared/log
      mkdir -p /etc/service/cloudflared/log/main
      cat <<RUNIT >/etc/service/cloudflared/log/run
#!/bin/sh
exec svlogd -tt ./main
RUNIT
      chmod +x /etc/service/cloudflared/log/run
fi


fi
# subspace service
if ! test -d /etc/service/subspace; then
  mkdir /etc/service/subspace
  cat <<RUNIT >/etc/service/subspace/run
#!/bin/sh
exec /usr/bin/subspace \
    "--http-host=${SUBSPACE_HTTP_HOST}" \
    "--http-addr=${SUBSPACE_HTTP_ADDR}" \
    "--http-insecure=${SUBSPACE_HTTP_INSECURE}" \
    "--backlink=${SUBSPACE_BACKLINK}" \
    "--letsencrypt=${SUBSPACE_LETSENCRYPT}"
RUNIT
  chmod +x /etc/service/subspace/run

  # subspace service log
  mkdir /etc/service/subspace/log
  mkdir /etc/service/subspace/log/main
  cat <<RUNIT >/etc/service/subspace/log/run
#!/bin/sh
exec svlogd -tt ./main
RUNIT
  chmod +x /etc/service/subspace/log/run
fi

exec $@
