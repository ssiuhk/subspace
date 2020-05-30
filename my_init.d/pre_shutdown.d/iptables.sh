#!/usr/bin/env sh
# Detect if iptables is using nft or legacy
if [ -x /sbin/iptables ]; then
  IPTABLES="/sbin/iptables"
  if [ -x /sbin/iptables-nft ]; then
    if [ $(/sbin/iptables-nft -vnL | egrep -c 'docker|!docker') -ge 2 ]; then
      IPTABLES="/sbin/iptables-nft"
    fi
  fi
fi

if [ -x /sbin/ip6tables ]; then
  IP6TABLES="/sbin/ip6tables"
  if [ -x /sbin/ip6tables-nft ]; then
    if [ $(/sbin/ip6tables-nft -vnL | egrep -c 'docker|!docker') -ge 2 ]; then
      IP6TABLES="/sbin/ip6tables-nft"
    fi
  fi
fi


# IPv4
if [ -x ${IPTABLES} ]; then
  if ${IPTABLES} -t nat --check POSTROUTING -s ${SUBSPACE_IPV4_POOL} -j MASQUERADE; then
    ${IPTABLES} -t nat --delete POSTROUTING -s ${SUBSPACE_IPV4_POOL} -j MASQUERADE
  fi

  if ${IPTABLES} --check FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT; then
    ${IPTABLES} --delete FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
  fi

  if ${IPTABLES} --check FORWARD -s ${SUBSPACE_IPV4_POOL} -j ACCEPT; then
    ${IPTABLES} --delete FORWARD -s ${SUBSPACE_IPV4_POOL} -j ACCEPT
  fi
else
  echo "Unable to find ${IPTABLES} not configuring IPv4 Rules"
fi

if [[ ${SUBSPACE_IPV6_NAT_ENABLED-} -gt 0 ]]; then
  # IPv6
  if [ -x ${IP6TABLES} ]; then
    if ${IP6TABLES} -t nat --check POSTROUTING -s ${SUBSPACE_IPV6_POOL} -j MASQUERADE; then
      ${IP6TABLES} -t nat --delete POSTROUTING -s ${SUBSPACE_IPV6_POOL} -j MASQUERADE
    fi

    if ${IP6TABLES} --check FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT; then
      ${IP6TABLES} --delete FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi

    if ${IP6TABLES} --check FORWARD -s ${SUBSPACE_IPV6_POOL} -j ACCEPT; then
      ${IP6TABLES} --delete FORWARD -s ${SUBSPACE_IPV6_POOL} -j ACCEPT
    fi
  else
    echo "Unable to find ${IP6TABLES} not configuring IPv6 Rules"
  fi
fi

if ${IPTABLES} -t nat --check OUTPUT -s ${SUBSPACE_IPV4_POOL} -p udp --dport 53 -j DNAT --to ${SUBSPACE_IPV4_GW}:53; then
  ${IPTABLES} -t nat --delete OUTPUT -s ${SUBSPACE_IPV4_POOL} -p udp --dport 53 -j DNAT --to ${SUBSPACE_IPV4_GW}:53
fi

if ${IPTABLES} -t nat --check OUTPUT -s ${SUBSPACE_IPV4_POOL} -p tcp --dport 53 -j DNAT --to ${SUBSPACE_IPV4_GW}:53; then
  ${IPTABLES} -t nat --delete OUTPUT -s ${SUBSPACE_IPV4_POOL} -p tcp --dport 53 -j DNAT --to ${SUBSPACE_IPV4_GW}:53
fi

if [[ ${SUBSPACE_IPV6_NAT_ENABLED-} -gt 0 ]]; then
  # ipv6 - DNS Leak Protection
  if ${IP6TABLES} --wait -t nat --check OUTPUT -s ${SUBSPACE_IPV6_POOL} -p udp --dport 53 -j DNAT --to ${SUBSPACE_IPV6_GW}; then
    ${IP6TABLES} --wait -t nat --delete OUTPUT -s ${SUBSPACE_IPV6_POOL} -p udp --dport 53 -j DNAT --to ${SUBSPACE_IPV6_GW}
  fi

  if ${IP6TABLES} --wait -t nat --check OUTPUT -s ${SUBSPACE_IPV6_POOL} -p tcp --dport 53 -j DNAT --to ${SUBSPACE_IPV6_GW}; then
    ${IP6TABLES} --wait -t nat --delete OUTPUT -s ${SUBSPACE_IPV6_POOL} -p tcp --dport 53 -j DNAT --to ${SUBSPACE_IPV6_GW}
  fi
fi

