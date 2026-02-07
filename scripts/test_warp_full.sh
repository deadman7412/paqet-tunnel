#!/usr/bin/env bash
set -euo pipefail

echo "=== WARP FULL DIAGNOSTICS ==="
MARK=51820
MARK_HEX="$(printf '0x%x' "${MARK}")"
PAQET_UID=""
if id -u paqet >/dev/null 2>&1; then
  PAQET_UID="$(id -u paqet)"
fi

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
if ip rule show | grep -q "fwmark"; then
  ip rule show | grep "fwmark"
else
  echo "(no fwmark rule)"
fi
if ip rule show | grep -q "uidrange"; then
  ip rule show | grep "uidrange"
else
  echo "(no uidrange rule)"
fi
ip route show table 51820 || echo "(no routes in table 51820)"

# 3) iptables mark rule
echo "\n[3] iptables mark rule"
if [ -n "${PAQET_UID}" ]; then
  iptables -t mangle -S OUTPUT \
    | grep -E "uid-owner (paqet|${PAQET_UID}).*(set-mark ${MARK}|set-xmark ${MARK_HEX}/0xffffffff)" \
    || echo "(no iptables mark rule)"
else
  iptables -t mangle -S OUTPUT \
    | grep -E "set-mark ${MARK}|set-xmark ${MARK_HEX}/0xffffffff" \
    || echo "(no iptables mark rule)"
fi

# 4) iptables counters
echo "\n[4] iptables counters"
iptables -t mangle -L OUTPUT -n -v | grep -E "MARK.*(${MARK}|${MARK_HEX})|owner UID match" || echo "(no counters)"

# 5) nft mark rule
if command -v nft >/dev/null 2>&1; then
  echo "\n[5] nft mark rule"
  if id -u paqet >/dev/null 2>&1; then
    PAQET_UID="$(id -u paqet)"
    nft -a list chain inet mangle output 2>/dev/null | grep -E "skuid ${PAQET_UID}.*mark set" || echo "(no nft mark rule)"
  else
    echo "(user paqet not found)"
  fi
fi

# 6) WARP egress direct
echo "\n[6] curl --interface wgcf"
WGCF_TRACE="$(curl --interface wgcf -s --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace || true)"
if [ -z "${WGCF_TRACE}" ]; then
  WGCF_TRACE="$(curl --interface wgcf -fsSL --connect-timeout 5 --max-time 12 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"
fi
if [ -z "${WGCF_TRACE}" ]; then
  WGCF_TRACE="$(curl --interface wgcf -fsSL --connect-timeout 5 --max-time 12 http://1.1.1.1/cdn-cgi/trace 2>/dev/null || true)"
fi
echo "${WGCF_TRACE}"

# 7) WARP egress as paqet
PAQET_TRACE=""
if id -u paqet >/dev/null 2>&1; then
  echo "\n[7] curl as user 'paqet'"
  PAQET_TRACE="$(sudo -u paqet curl -fsSL --connect-timeout 5 --max-time 12 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"
  if [ -z "${PAQET_TRACE}" ]; then
    PAQET_TRACE="$(sudo -u paqet curl -fsSL --connect-timeout 5 --max-time 12 http://1.1.1.1/cdn-cgi/trace 2>/dev/null || true)"
  fi
  echo "${PAQET_TRACE}"
else
  echo "\n[7] user 'paqet' not found"
fi

# Summary
echo "\n[9] Summary"
if echo "${WGCF_TRACE}" | grep -q "warp=on"; then
  echo "WARP interface: OK (warp=on)"
else
  echo "WARP interface: NOT OK (warp=off or no response)"
fi

if [ -n "${PAQET_TRACE}" ]; then
  if echo "${PAQET_TRACE}" | grep -q "warp=on"; then
    echo "paqet traffic: OK (warp=on)"
  else
    echo "paqet traffic: NOT using WARP (warp=off)"
    echo "Note: If uidrange rule is missing or unsupported, paqet may bypass WARP."
  fi
else
  echo "paqet traffic: NOT TESTED (user missing or curl failed)"
fi

# 8) MTU checks
echo "\n[8] MTU"
if [ -f /etc/wireguard/wgcf.conf ]; then
  grep -E '^MTU' /etc/wireguard/wgcf.conf || echo "(no MTU in wgcf.conf)"
fi
ip link show wgcf 2>/dev/null | grep mtu || true

echo "\n=== END ==="
