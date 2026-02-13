#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="icmptunnel-${ROLE}"
ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
ICMPTUNNEL_POLICY_STATE_DIR="/etc/icmptunnel-policy"
ICMPTUNNEL_POLICY_STATE_FILE="${ICMPTUNNEL_POLICY_STATE_DIR}/settings.env"

TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${ICMPTUNNEL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${ICMPTUNNEL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${ICMPTUNNEL_POLICY_STATE_FILE}"
  chmod 600 "${ICMPTUNNEL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if [ ! -f /etc/wireguard/wgcf.conf ]; then
  echo "WARP core is not installed." >&2
  echo "Run: Paqet Tunnel -> WARP/DNS core -> Install WARP core" >&2
  exit 1
fi

if ! ip link show wgcf >/dev/null 2>&1; then
  wg-quick up wgcf >/dev/null 2>&1 || {
    echo "wgcf interface is not active and could not be started." >&2
    exit 1
  }
fi

if [ -f /etc/iproute2/rt_tables ]; then
  if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
    echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
  fi
fi

if ! ip route show table ${TABLE_ID} 2>/dev/null | grep -q '^default '; then
  ip route add default dev wgcf table ${TABLE_ID}
fi

if ! id -u icmptunnel >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin icmptunnel
fi
ICMPTUNNEL_UID="$(id -u icmptunnel)"

ICMPTUNNEL_SRC_DIR="${ICMPTUNNEL_DIR}"
ICMPTUNNEL_DST_DIR="/opt/icmptunnel"
ICMPTUNNEL_BIN_SRC="${ICMPTUNNEL_SRC_DIR}/icmptunnel"
ICMPTUNNEL_CFG_SRC="${ICMPTUNNEL_SRC_DIR}/${ROLE}/config.json"
ICMPTUNNEL_BIN_DST="${ICMPTUNNEL_DST_DIR}/icmptunnel"
ICMPTUNNEL_CFG_DST="${ICMPTUNNEL_DST_DIR}/${ROLE}/config.json"

if [ -x "${ICMPTUNNEL_BIN_SRC}" ] && [ -f "${ICMPTUNNEL_CFG_SRC}" ]; then
  mkdir -p "${ICMPTUNNEL_DST_DIR}/${ROLE}"
  cp -f "${ICMPTUNNEL_BIN_SRC}" "${ICMPTUNNEL_BIN_DST}"
  cp -f "${ICMPTUNNEL_CFG_SRC}" "${ICMPTUNNEL_CFG_DST}"
  chown root:icmptunnel "${ICMPTUNNEL_BIN_DST}" "${ICMPTUNNEL_CFG_DST}" 2>/dev/null || true
  chmod 750 "${ICMPTUNNEL_BIN_DST}" || true
  chmod 640 "${ICMPTUNNEL_CFG_DST}" || true
else
  echo "Warning: icmptunnel binary/config not found at ${ICMPTUNNEL_SRC_DIR}. Service may fail to start." >&2
fi

if ! command -v setcap >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y libcap2-bin
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y libcap
  elif command -v yum >/dev/null 2>&1; then
    yum install -y libcap
  fi
fi
if [ -x "${ICMPTUNNEL_BIN_DST}" ] && command -v setcap >/dev/null 2>&1; then
  setcap cap_net_raw,cap_net_admin=ep "${ICMPTUNNEL_BIN_DST}" || true
fi

UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
mkdir -p "${DROPIN_DIR}"
cat <<CONF > "${DROPIN_DIR}/10-warp.conf"
[Service]
User=icmptunnel
Group=icmptunnel
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
WorkingDirectory=${ICMPTUNNEL_DST_DIR}/${ROLE}
ExecStart=
ExecStart=${ICMPTUNNEL_BIN_DST}
CONF

if [ -f "${UNIT}" ]; then
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
else
  echo "Note: ${SERVICE_NAME}.service not installed yet. WARP drop-in is prepared and will apply after service install."
fi

while ip rule show | grep -Eq "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}.*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table ${TABLE_ID} 2>/dev/null || ip rule del uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table wgcf 2>/dev/null || true
done
if ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table ${TABLE_ID} 2>/dev/null; then
  echo "uidrange rule added for icmptunnel user (${ICMPTUNNEL_UID})."
else
  echo "Warning: uidrange rule not supported or failed to add." >&2
fi

while ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark 0xca6c table wgcf 2>/dev/null || true
done
while iptables -t mangle -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
while iptables -t mangle -D OUTPUT -m owner --uid-owner icmptunnel -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
if command -v nft >/dev/null 2>&1; then
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule ip mangle OUTPUT handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain ip mangle OUTPUT 2>/dev/null | awk -v uid="${ICMPTUNNEL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${ICMPTUNNEL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
fi

echo "WARP routing mode: uidrange-only (no iptables rules - SSH approach)."
echo "Note: ICMP NOTRACK rules skipped (not needed, causes nftables conflicts)."

set_state "icmptunnel_warp_enabled" "1"

echo "WARP binding enabled for ${SERVICE_NAME}."
