#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="waterwall-direct-${ROLE}"
WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
WATERWALL_POLICY_STATE_DIR="/etc/waterwall-policy"
WATERWALL_POLICY_STATE_FILE="${WATERWALL_POLICY_STATE_DIR}/settings.env"

TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${WATERWALL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${WATERWALL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${WATERWALL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${WATERWALL_POLICY_STATE_FILE}"
  chmod 600 "${WATERWALL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if ! id -u waterwall >/dev/null 2>&1; then
  echo "waterwall user does not exist. Nothing to disable." >&2
  set_state "waterwall_warp_enabled" "0"
  exit 0
fi

WATERWALL_UID="$(id -u waterwall)"

while ip rule show | grep -Eq "uidrange ${WATERWALL_UID}-${WATERWALL_UID}.*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del uidrange ${WATERWALL_UID}-${WATERWALL_UID} table ${TABLE_ID} 2>/dev/null || ip rule del uidrange ${WATERWALL_UID}-${WATERWALL_UID} table wgcf 2>/dev/null || true
done

while ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark 0xca6c table wgcf 2>/dev/null || true
done

while iptables -t mangle -D OUTPUT -m owner --uid-owner "${WATERWALL_UID}" -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
while iptables -t mangle -D OUTPUT -m owner --uid-owner waterwall -j MARK --set-mark ${MARK} 2>/dev/null; do :; done

if command -v nft >/dev/null 2>&1; then
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule ip mangle OUTPUT handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain ip mangle OUTPUT 2>/dev/null | awk -v uid="${WATERWALL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${WATERWALL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
fi

DROPIN_FILE="/etc/systemd/system/${SERVICE_NAME}.service.d/10-warp.conf"
if [ -f "${DROPIN_FILE}" ]; then
  rm -f "${DROPIN_FILE}"
  systemctl daemon-reload
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    systemctl restart "${SERVICE_NAME}.service" || true
  fi
fi

if iptables -V 2>/dev/null | grep -qi nf_tables; then
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
    systemctl enable --now nftables >/dev/null 2>&1 || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 || true
  elif command -v service >/dev/null 2>&1; then
    service iptables save || true
  fi
fi

set_state "waterwall_warp_enabled" "0"

echo "WARP binding disabled for ${SERVICE_NAME}."
