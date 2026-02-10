#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
SERVER_POLICY_STATE_DIR="/etc/paqet-policy"
SERVER_POLICY_STATE_FILE="${SERVER_POLICY_STATE_DIR}/settings.env"

TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

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

ensure_server_iptables_rules() {
  local port=""
  local info_file="${PAQET_DIR}/server_info.txt"
  local cfg_file="${PAQET_DIR}/server.yaml"

  if [ -f "${cfg_file}" ]; then
    port="$(awk '
      $1 == "listen:" { inlisten=1; next }
      inlisten && $1 == "addr:" {
        gsub(/"/, "", $2);
        sub(/^:/, "", $2);
        print $2;
        exit
      }
    ' "${cfg_file}")"
  fi
  if [ -z "${port}" ] && [ -f "${info_file}" ]; then
    port="$(awk -F= '/^listen_port=/{print $2; exit}' "${info_file}")"
  fi
  if [ -z "${port}" ]; then
    echo "Warning: could not detect server listen port for iptables checks." >&2
    return 0
  fi

  while iptables -t raw -C PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null; do
    iptables -t raw -D PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null || true
  done
  iptables -t raw -A PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null || true

  while iptables -t raw -C OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null; do
    iptables -t raw -D OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null || true
  done
  iptables -t raw -A OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null || true

  while iptables -t mangle -C OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null; do
    iptables -t mangle -D OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null || true
  done
  iptables -t mangle -A OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null || true
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

if ! id -u paqet >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin paqet
fi
PAQET_UID="$(id -u paqet)"

PAQET_SRC_DIR="${PAQET_DIR}"
PAQET_DST_DIR="/opt/paqet"
PAQET_BIN_SRC="${PAQET_SRC_DIR}/paqet"
PAQET_CFG_SRC="${PAQET_SRC_DIR}/server.yaml"
PAQET_BIN_DST="${PAQET_DST_DIR}/paqet"
PAQET_CFG_DST="${PAQET_DST_DIR}/server.yaml"

if [ -x "${PAQET_BIN_SRC}" ] && [ -f "${PAQET_CFG_SRC}" ]; then
  mkdir -p "${PAQET_DST_DIR}"
  cp -f "${PAQET_BIN_SRC}" "${PAQET_BIN_DST}"
  cp -f "${PAQET_CFG_SRC}" "${PAQET_CFG_DST}"
  chown root:paqet "${PAQET_BIN_DST}" "${PAQET_CFG_DST}" 2>/dev/null || true
  chmod 750 "${PAQET_BIN_DST}" || true
  chmod 640 "${PAQET_CFG_DST}" || true
else
  echo "Warning: paqet binary/config not found at ${PAQET_SRC_DIR}. Service may fail to start." >&2
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
if [ -x "${PAQET_BIN_DST}" ] && command -v setcap >/dev/null 2>&1; then
  setcap cap_net_raw,cap_net_admin=ep "${PAQET_BIN_DST}" || true
fi

UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
mkdir -p "${DROPIN_DIR}"
cat <<CONF > "${DROPIN_DIR}/10-warp.conf"
[Service]
User=paqet
Group=paqet
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
WorkingDirectory=${PAQET_DST_DIR}
ExecStart=
ExecStart=${PAQET_BIN_DST} run -c ${PAQET_CFG_DST}
CONF
if [ -f "${UNIT}" ]; then
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
else
  echo "Note: ${SERVICE_NAME}.service not installed yet. WARP drop-in is prepared and will apply after service install."
fi

while ip rule show | grep -Eq "uidrange ${PAQET_UID}-${PAQET_UID}.*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del uidrange ${PAQET_UID}-${PAQET_UID} table ${TABLE_ID} 2>/dev/null || ip rule del uidrange ${PAQET_UID}-${PAQET_UID} table wgcf 2>/dev/null || true
done
if ip rule add uidrange ${PAQET_UID}-${PAQET_UID} table ${TABLE_ID} 2>/dev/null; then
  echo "uidrange rule added for paqet user (${PAQET_UID})."
else
  echo "Warning: uidrange rule not supported or failed to add." >&2
fi

while ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark 0xca6c table wgcf 2>/dev/null || true
done
while iptables -t mangle -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
while iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
if command -v nft >/dev/null 2>&1; then
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule ip mangle OUTPUT handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain ip mangle OUTPUT 2>/dev/null | awk -v uid="${PAQET_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${PAQET_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
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

set_state "server_warp_enabled" "1"

echo "WARP binding enabled for ${SERVICE_NAME}."
