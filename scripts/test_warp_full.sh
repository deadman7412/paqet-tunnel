#!/usr/bin/env bash
set -euo pipefail

echo "=== WARP FULL DIAGNOSTICS ==="

# Backend info
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  echo "iptables backend: nft"
else
  echo "iptables backend: legacy"
fi

# 1) WireGuard status
if command -v wg >/dev/null 2>&1; then
  echo "\n[1] wg show wgcf"
  wg show wgcf || echo "wgcf interface not active"
else
  echo "wg not available"
fi

# 2) Policy routing
echo "\n[2] Policy routing"
ip rule show | grep 51820 || echo "(no fwmark rule)"
ip route show table 51820 || echo "(no routes in table 51820)"

# 3) iptables mark rule
echo "\n[3] iptables mark rule"
iptables -t mangle -S OUTPUT | grep -E 'owner --uid-owner paqet|MARK --set-mark 51820' || echo "(no iptables mark rule)"

# 4) iptables counters
echo "\n[4] iptables counters"
iptables -t mangle -L OUTPUT -n -v | grep -E 'MARK.*51820|uid-owner paqet' || echo "(no counters)"

# 5) nft mark rule
if command -v nft >/dev/null 2>&1; then
  echo "\n[5] nft mark rule"
  if id -u paqet >/dev/null 2>&1; then
    PAQET_UID="$(id -u paqet)"
    nft list chain inet mangle output 2>/dev/null | grep -E "skuid ${PAQET_UID}.*mark set" || echo "(no nft mark rule)"
  else
    echo "(user paqet not found)"
  fi
fi

# 6) WARP egress direct
echo "\n[6] curl --interface wgcf"
curl -v --interface wgcf --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace || true

# 7) WARP egress as paqet
if id -u paqet >/dev/null 2>&1; then
  echo "\n[7] curl as user 'paqet'"
  sudo -u paqet curl -v --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace || true
else
  echo "\n[7] user 'paqet' not found"
fi

# 8) MTU checks
echo "\n[8] MTU"
if [ -f /etc/wireguard/wgcf.conf ]; then
  grep -E '^MTU' /etc/wireguard/wgcf.conf || echo "(no MTU in wgcf.conf)"
fi
ip link show wgcf 2>/dev/null | grep mtu || true

echo "\n=== END ==="
