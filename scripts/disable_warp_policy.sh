#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"
SERVER_POLICY_STATE_DIR="/etc/paqet-policy"
SERVER_POLICY_STATE_FILE="${SERVER_POLICY_STATE_DIR}/settings.env"
TABLE_ID=51820
MARK=51820

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${SERVER_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${SERVER_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${SERVER_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${SERVER_POLICY_STATE_FILE}"
  chmod 600 "${SERVER_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true
if id -u paqet >/dev/null 2>&1; then
  PAQET_UID="$(id -u paqet)"
  while iptables -t mangle -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
fi

if command -v nft >/dev/null 2>&1; then
  if id -u paqet >/dev/null 2>&1; then
    PAQET_UID="$(id -u paqet)"
    while read -r handle; do
      [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
    done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${PAQET_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
  else
    nft delete rule inet mangle output meta skuid "paqet" meta mark set ${MARK} 2>/dev/null || true
  fi
fi

while ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null; do :; done
while ip rule del fwmark 0xca6c table ${TABLE_ID} 2>/dev/null; do :; done
if id -u paqet >/dev/null 2>&1; then
  PAQET_UID="$(id -u paqet)"
  while ip rule del uidrange ${PAQET_UID}-${PAQET_UID} table ${TABLE_ID} 2>/dev/null; do :; done
  while ip rule del uidrange ${PAQET_UID}-${PAQET_UID} table wgcf 2>/dev/null; do :; done
fi

DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
if [ -f "${DROPIN_DIR}/10-warp.conf" ]; then
  rm -f "${DROPIN_DIR}/10-warp.conf"
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
fi

if iptables -V 2>/dev/null | grep -qi nf_tables; then
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
    systemctl enable --now nftables >/dev/null 2>&1 || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif command -v service >/dev/null 2>&1; then
    service iptables save || true
  fi
fi

set_state "server_warp_enabled" "0"

echo "WARP binding disabled for ${SERVICE_NAME}."
