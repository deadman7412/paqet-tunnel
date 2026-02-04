#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"

TABLE_ID=51820
MARK=51820

# Remove iptables mark rule
iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true

# Remove nft mark rule if present
if command -v nft >/dev/null 2>&1; then
  nft delete rule inet mangle output meta skuid \"paqet\" meta mark set ${MARK} 2>/dev/null || true
fi

# Remove ip rule and route table
ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || true
ip route flush table ${TABLE_ID} 2>/dev/null || true

# Bring down wgcf
wg-quick down wgcf >/dev/null 2>&1 || true

# Remove systemd drop-in if present
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
if [ -f "${DROPIN_DIR}/10-warp.conf" ]; then
  rm -f "${DROPIN_DIR}/10-warp.conf"
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
fi

# Save iptables if persistence is installed
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif command -v service >/dev/null 2>&1; then
  service iptables save || true
fi

# Persist nft rule removal
if command -v nft >/dev/null 2>&1 && [ -f /etc/nftables.conf ]; then
  nft list ruleset > /etc/nftables.conf || true
  systemctl enable --now nftables >/dev/null 2>&1 || true
fi

echo "WARP policy routing disabled for ${SERVICE_NAME}."
