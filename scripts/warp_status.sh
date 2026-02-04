#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"

echo "Service: ${SERVICE_NAME}"

if command -v wg >/dev/null 2>&1; then
  echo
  echo "WireGuard (wgcf) status:"
  wg show wgcf || echo "wgcf interface not active"
else
  echo "wg not available"
fi

WGCF_CONF="/etc/wireguard/wgcf.conf"
if [ -f "${WGCF_CONF}" ]; then
  MTU_CONF="$(sed -n 's/^MTU[[:space:]]*=[[:space:]]*//p' "${WGCF_CONF}" | head -n1)"
  if [ -n "${MTU_CONF}" ]; then
    echo
    echo "wgcf.conf MTU: ${MTU_CONF}"
  fi
fi

echo
echo "Policy routing rules:"
ip rule show | grep -E "fwmark 51820" || echo "(no fwmark rule)"

ip route show table 51820 || echo "(no routes in table 51820)"

echo
echo "iptables mark rules:"
if iptables -t mangle -S OUTPUT | grep -E "owner --uid-owner paqet|MARK --set-mark 51820" >/dev/null; then
  iptables -t mangle -S OUTPUT | grep -E "owner --uid-owner paqet|MARK --set-mark 51820"
else
  echo "(no mark rules) - WARP will NOT route paqet traffic"
fi

if command -v nft >/dev/null 2>&1; then
  echo
  echo "nft mark rules:"
  if nft list chain inet mangle output 2>/dev/null | grep -q "skuid \"paqet\".*mark set 51820"; then
    nft list chain inet mangle output 2>/dev/null | grep "skuid \"paqet\".*mark set 51820"
  else
    echo "(no nft mark rules)"
  fi
fi
