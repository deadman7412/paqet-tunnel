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

ensure_server_iptables_rules() {
  local port=""
  local info_file="${WATERWALL_DIR}/direct_server_info.txt"
  local cfg_file="${WATERWALL_DIR}/server/config.json"

  if [ -f "${cfg_file}" ]; then
    port="$(python3 -c "
import json
try:
    with open('${cfg_file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    if nodes:
        listener = nodes[0].get('settings', {})
        print(listener.get('port', ''))
except:
    pass
" 2>/dev/null || true)"
  fi
  if [ -z "${port}" ] && [ -f "${info_file}" ]; then
    port="$(awk -F= '/^listen_port=/{print $2; exit}' "${info_file}")"
  fi
  if [ -z "${port}" ]; then
    echo "[WARN] Could not detect server listen port for iptables optimization." >&2
    echo "[INFO] Skipping NOTRACK rules (not critical for functionality)." >&2
    return 0
  fi

  echo
  echo "[DEBUG] Configuring iptables optimization rules for port ${port}..."

  # Detect nftables backend
  local using_nftables="false"
  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    using_nftables="true"
    echo "[INFO] Detected nftables backend - NOTRACK rules may not be supported"
  fi

  # NOTRACK rules for performance (reduce connection tracking overhead)
  echo "[DEBUG] Adding NOTRACK rule: PREROUTING (inbound to port ${port})..."
  while iptables -t raw -C PREROUTING -p tcp --dport "${port}" -m comment --comment waterwall-notrack-in -j NOTRACK 2>/dev/null; do
    iptables -t raw -D PREROUTING -p tcp --dport "${port}" -m comment --comment waterwall-notrack-in -j NOTRACK 2>/dev/null || true
  done
  if iptables -t raw -A PREROUTING -p tcp --dport "${port}" -m comment --comment waterwall-notrack-in -j NOTRACK 2>&1; then
    echo "[SUCCESS] NOTRACK PREROUTING rule added"
  else
    echo "[WARN] NOTRACK PREROUTING rule failed (expected on nftables systems)" >&2
  fi

  echo "[DEBUG] Adding NOTRACK rule: OUTPUT (outbound from port ${port})..."
  while iptables -t raw -C OUTPUT -p tcp --sport "${port}" -m comment --comment waterwall-notrack-out -j NOTRACK 2>/dev/null; do
    iptables -t raw -D OUTPUT -p tcp --sport "${port}" -m comment --comment waterwall-notrack-out -j NOTRACK 2>/dev/null || true
  done
  if iptables -t raw -A OUTPUT -p tcp --sport "${port}" -m comment --comment waterwall-notrack-out -j NOTRACK 2>&1; then
    echo "[SUCCESS] NOTRACK OUTPUT rule added"
  else
    echo "[WARN] NOTRACK OUTPUT rule failed (expected on nftables systems)" >&2
  fi

  # RST drop rule for TCP connection cleanup
  echo "[DEBUG] Adding RST drop rule for port ${port}..."
  while iptables -t mangle -C OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment waterwall-rst-drop -j DROP 2>/dev/null; do
    iptables -t mangle -D OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment waterwall-rst-drop -j DROP 2>/dev/null || true
  done
  if iptables -t mangle -A OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment waterwall-rst-drop -j DROP 2>&1; then
    echo "[SUCCESS] RST drop rule added"
  else
    echo "[WARN] RST drop rule failed" >&2
  fi

  # Verify rules
  echo
  echo "[DEBUG] Verifying iptables rules were added:"
  echo "[DEBUG] raw table NOTRACK rules:"
  iptables -t raw -L PREROUTING -n -v 2>/dev/null | grep -i "waterwall-notrack" | sed 's/^/  /' || echo "  (none found)"
  iptables -t raw -L OUTPUT -n -v 2>/dev/null | grep -i "waterwall-notrack" | sed 's/^/  /' || echo "  (none found)"
  echo "[DEBUG] mangle table RST drop rules:"
  iptables -t mangle -L OUTPUT -n -v 2>/dev/null | grep -i "waterwall-rst" | sed 's/^/  /' || echo "  (none found)"

  if [ "${using_nftables}" = "true" ]; then
    echo
    echo "[INFO] System uses nftables backend - iptables raw table may not work"
    echo "[INFO] Service will work fine, but without NOTRACK optimization (slightly higher CPU usage)"
  fi
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

if ! id -u waterwall >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin waterwall
fi
WATERWALL_UID="$(id -u waterwall)"

WATERWALL_SRC_DIR="${WATERWALL_DIR}"
WATERWALL_DST_DIR="/opt/waterwall"
WATERWALL_BIN_SRC="${WATERWALL_SRC_DIR}/waterwall"
WATERWALL_CFG_SRC="${WATERWALL_SRC_DIR}/${ROLE}/config.json"
WATERWALL_CORE_SRC="${WATERWALL_SRC_DIR}/${ROLE}/core.json"
WATERWALL_BIN_DST="${WATERWALL_DST_DIR}/waterwall"
WATERWALL_CFG_DST="${WATERWALL_DST_DIR}/${ROLE}/config.json"
WATERWALL_CORE_DST="${WATERWALL_DST_DIR}/${ROLE}/core.json"

if [ -x "${WATERWALL_BIN_SRC}" ] && [ -f "${WATERWALL_CFG_SRC}" ]; then
  mkdir -p "${WATERWALL_DST_DIR}/${ROLE}/log" "${WATERWALL_DST_DIR}/${ROLE}/logs" "${WATERWALL_DST_DIR}/${ROLE}/runtime"
  cp -f "${WATERWALL_BIN_SRC}" "${WATERWALL_BIN_DST}"
  cp -f "${WATERWALL_CFG_SRC}" "${WATERWALL_CFG_DST}"
  if [ -f "${WATERWALL_CORE_SRC}" ]; then
    cp -f "${WATERWALL_CORE_SRC}" "${WATERWALL_CORE_DST}"
  fi
  chown root:waterwall "${WATERWALL_BIN_DST}" "${WATERWALL_CFG_DST}" 2>/dev/null || true
  [ -f "${WATERWALL_CORE_DST}" ] && chown root:waterwall "${WATERWALL_CORE_DST}" 2>/dev/null || true
  chmod 750 "${WATERWALL_BIN_DST}" || true
  chmod 640 "${WATERWALL_CFG_DST}" || true
  [ -f "${WATERWALL_CORE_DST}" ] && chmod 640 "${WATERWALL_CORE_DST}" || true
else
  echo "Warning: waterwall binary/config not found at ${WATERWALL_SRC_DIR}. Service may fail to start." >&2
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
if [ -x "${WATERWALL_BIN_DST}" ] && command -v setcap >/dev/null 2>&1; then
  setcap cap_net_raw,cap_net_admin=ep "${WATERWALL_BIN_DST}" || true
fi

UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
mkdir -p "${DROPIN_DIR}"
cat <<CONF > "${DROPIN_DIR}/10-warp.conf"
[Service]
User=waterwall
Group=waterwall
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
WorkingDirectory=${WATERWALL_DST_DIR}/${ROLE}
ExecStart=
ExecStart=${WATERWALL_BIN_DST}
CONF
if [ -f "${UNIT}" ]; then
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
else
  echo "Note: ${SERVICE_NAME}.service not installed yet. WARP drop-in is prepared and will apply after service install."
fi

while ip rule show | grep -Eq "uidrange ${WATERWALL_UID}-${WATERWALL_UID}.*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del uidrange ${WATERWALL_UID}-${WATERWALL_UID} table ${TABLE_ID} 2>/dev/null || ip rule del uidrange ${WATERWALL_UID}-${WATERWALL_UID} table wgcf 2>/dev/null || true
done
if ip rule add uidrange ${WATERWALL_UID}-${WATERWALL_UID} table ${TABLE_ID} 2>/dev/null; then
  echo "uidrange rule added for waterwall user (${WATERWALL_UID})."
else
  echo "Warning: uidrange rule not supported or failed to add." >&2
fi

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

echo "WARP routing mode: uidrange-only (no MARK rules)."

ensure_server_iptables_rules
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

set_state "waterwall_warp_enabled" "1"

echo "WARP binding enabled for ${SERVICE_NAME}."
