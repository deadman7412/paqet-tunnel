#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
OUT_FILE="${PAQET_DIR}/client.yaml"
INFO_FILE="${PAQET_DIR}/server_info.txt"

backup_file_if_exists() {
  local file="$1"
  if [ -f "${file}" ]; then
    local ts backup
    ts="$(date -u +"%Y%m%d-%H%M%S")"
    backup="${file}.bak.${ts}"
    cp -f "${file}" "${backup}"
    echo "Backup created: ${backup}"
  fi
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_mode() {
  case "$1" in
    normal|fast|fast2|fast3|manual) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -f "${OUT_FILE}" ]; then
  read -r -p "${OUT_FILE} exists. Overwrite? [y/N]: " ow
  case "${ow}" in
    y|Y) backup_file_if_exists "${OUT_FILE}" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

IFACE_DEFAULT=""
if command -v ip >/dev/null 2>&1; then
  IFACE_DEFAULT="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
fi

read -r -p "Network interface [${IFACE_DEFAULT}]: " IFACE
IFACE="${IFACE:-${IFACE_DEFAULT}}"
if [ -z "${IFACE}" ]; then
  echo "Network interface is required." >&2
  exit 1
fi

LOCAL_IP_DEFAULT=""
if [ -n "${IFACE}" ] && command -v ip >/dev/null 2>&1; then
  LOCAL_IP_DEFAULT="$(ip -4 addr show dev "${IFACE}" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1)"
fi
read -r -p "Local IPv4 [${LOCAL_IP_DEFAULT}]: " LOCAL_IP
LOCAL_IP="${LOCAL_IP:-${LOCAL_IP_DEFAULT}}"
if [ -z "${LOCAL_IP}" ]; then
  echo "Local IPv4 is required." >&2
  exit 1
fi

GW_IP=""
if command -v ip >/dev/null 2>&1; then
  GW_IP="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
fi

GW_MAC_DEFAULT=""
if [ -n "${GW_IP}" ] && command -v ip >/dev/null 2>&1; then
  GW_MAC_DEFAULT="$(ip neigh show "${GW_IP}" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") {print $(i+1); exit}}')"
fi
read -r -p "Gateway MAC [${GW_MAC_DEFAULT}]: " GW_MAC
GW_MAC="${GW_MAC:-${GW_MAC_DEFAULT}}"
if [ -z "${GW_MAC}" ]; then
  echo "Gateway MAC is required." >&2
  exit 1
fi

PORT_DEFAULT="9999"
KCP_KEY_DEFAULT=""
KCP_MODE_DEFAULT="fast"
KCP_CONN_DEFAULT="1"
MTU_DEFAULT="1350"
KCP_RCVWND_DEFAULT="1024"
KCP_SNDWND_DEFAULT="1024"
KCP_NODELAY_DEFAULT="1"
KCP_INTERVAL_DEFAULT="10"
KCP_RESEND_DEFAULT="2"
KCP_NO_CONGESTION_DEFAULT="1"
KCP_WDELAY_DEFAULT="false"
KCP_ACK_NODELAY_DEFAULT="true"

if [ -f "${INFO_FILE}" ]; then
  INFO_FORMAT_VERSION="$(awk -F= '/^format_version=/{print $2; exit}' "${INFO_FILE}")"
  INFO_CREATED_AT="$(awk -F= '/^created_at=/{print $2; exit}' "${INFO_FILE}")"
  PORT_DEFAULT="$(awk -F= '/^listen_port=/{print $2; exit}' "${INFO_FILE}")"
  KCP_KEY_DEFAULT="$(awk -F= '/^kcp_key=/{print $2; exit}' "${INFO_FILE}")"
  KCP_MODE_DEFAULT="$(awk -F= '/^kcp_mode=/{print $2; exit}' "${INFO_FILE}")"
  KCP_CONN_DEFAULT="$(awk -F= '/^kcp_conn=/{print $2; exit}' "${INFO_FILE}")"
  MTU_DEFAULT="$(awk -F= '/^mtu=/{print $2; exit}' "${INFO_FILE}")"
  KCP_RCVWND_DEFAULT="$(awk -F= '/^kcp_rcvwnd=/{print $2; exit}' "${INFO_FILE}")"
  KCP_SNDWND_DEFAULT="$(awk -F= '/^kcp_sndwnd=/{print $2; exit}' "${INFO_FILE}")"
  KCP_NODELAY_DEFAULT="$(awk -F= '/^kcp_nodelay=/{print $2; exit}' "${INFO_FILE}")"
  KCP_INTERVAL_DEFAULT="$(awk -F= '/^kcp_interval=/{print $2; exit}' "${INFO_FILE}")"
  KCP_RESEND_DEFAULT="$(awk -F= '/^kcp_resend=/{print $2; exit}' "${INFO_FILE}")"
  KCP_NO_CONGESTION_DEFAULT="$(awk -F= '/^kcp_nocongestion=/{print $2; exit}' "${INFO_FILE}")"
  KCP_WDELAY_DEFAULT="$(awk -F= '/^kcp_wdelay=/{print $2; exit}' "${INFO_FILE}")"
  KCP_ACK_NODELAY_DEFAULT="$(awk -F= '/^kcp_acknodelay=/{print $2; exit}' "${INFO_FILE}")"

  SERVER_IP_DEFAULT="$(awk -F= '/^server_public_ip=/{print $2; exit}' "${INFO_FILE}")"
  if [ "${SERVER_IP_DEFAULT}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
    SERVER_IP_DEFAULT=""
  fi

  PORT_DEFAULT="${PORT_DEFAULT:-9999}"
  KCP_MODE_DEFAULT="${KCP_MODE_DEFAULT:-fast}"
  KCP_CONN_DEFAULT="${KCP_CONN_DEFAULT:-1}"
  MTU_DEFAULT="${MTU_DEFAULT:-1350}"
  KCP_RCVWND_DEFAULT="${KCP_RCVWND_DEFAULT:-1024}"
  KCP_SNDWND_DEFAULT="${KCP_SNDWND_DEFAULT:-1024}"
  KCP_NODELAY_DEFAULT="${KCP_NODELAY_DEFAULT:-1}"
  KCP_INTERVAL_DEFAULT="${KCP_INTERVAL_DEFAULT:-10}"
  KCP_RESEND_DEFAULT="${KCP_RESEND_DEFAULT:-2}"
  KCP_NO_CONGESTION_DEFAULT="${KCP_NO_CONGESTION_DEFAULT:-1}"
  KCP_WDELAY_DEFAULT="${KCP_WDELAY_DEFAULT:-false}"
  KCP_ACK_NODELAY_DEFAULT="${KCP_ACK_NODELAY_DEFAULT:-true}"

  echo "Loaded defaults from ${INFO_FILE}"
  if [ -n "${INFO_FORMAT_VERSION:-}" ] && [ "${INFO_FORMAT_VERSION}" != "1" ]; then
    echo "Warning: server_info format_version=${INFO_FORMAT_VERSION} (expected 1). Proceeding with compatible keys."
  fi
  if [ -n "${INFO_CREATED_AT:-}" ]; then
    echo "server_info created_at: ${INFO_CREATED_AT}"
  fi
else
  SERVER_IP_DEFAULT=""
fi

read -r -p "Server public IP [${SERVER_IP_DEFAULT}]: " SERVER_IP
SERVER_IP="${SERVER_IP:-${SERVER_IP_DEFAULT}}"
if [ -z "${SERVER_IP}" ]; then
  echo "Server public IP is required." >&2
  exit 1
fi

read -r -p "Server port [${PORT_DEFAULT}]: " PORT
PORT="${PORT:-${PORT_DEFAULT}}"
if ! is_number "${PORT}" || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  echo "Server port must be 1-65535." >&2
  exit 1
fi

read -r -p "SOCKS5 listen [127.0.0.1:1080]: " SOCKS_LISTEN
SOCKS_LISTEN="${SOCKS_LISTEN:-127.0.0.1:1080}"

read -r -p "KCP mode [${KCP_MODE_DEFAULT}] (normal/fast/fast2/fast3/manual): " KCP_MODE
KCP_MODE="${KCP_MODE:-${KCP_MODE_DEFAULT}}"
if ! validate_mode "${KCP_MODE}"; then
  echo "Invalid KCP mode: ${KCP_MODE}" >&2
  exit 1
fi

read -r -p "KCP connections [${KCP_CONN_DEFAULT}] (1-256): " KCP_CONN
KCP_CONN="${KCP_CONN:-${KCP_CONN_DEFAULT}}"
if ! is_number "${KCP_CONN}" || [ "${KCP_CONN}" -lt 1 ] || [ "${KCP_CONN}" -gt 256 ]; then
  echo "KCP connections must be 1-256." >&2
  exit 1
fi

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [${MTU_DEFAULT}] (50-1500): " MTU
MTU="${MTU:-${MTU_DEFAULT}}"
if ! is_number "${MTU}" || [ "${MTU}" -lt 50 ] || [ "${MTU}" -gt 1500 ]; then
  echo "MTU must be 50-1500." >&2
  exit 1
fi

read -r -p "KCP receive window [${KCP_RCVWND_DEFAULT}]: " KCP_RCVWND
KCP_RCVWND="${KCP_RCVWND:-${KCP_RCVWND_DEFAULT}}"
if ! is_number "${KCP_RCVWND}" || [ "${KCP_RCVWND}" -lt 1 ]; then
  echo "KCP receive window must be a positive number." >&2
  exit 1
fi

read -r -p "KCP send window [${KCP_SNDWND_DEFAULT}]: " KCP_SNDWND
KCP_SNDWND="${KCP_SNDWND:-${KCP_SNDWND_DEFAULT}}"
if ! is_number "${KCP_SNDWND}" || [ "${KCP_SNDWND}" -lt 1 ]; then
  echo "KCP send window must be a positive number." >&2
  exit 1
fi

MANUAL_BLOCK=""
if [ "${KCP_MODE}" = "manual" ]; then
  echo "Manual mode selected. Use the same values as the server."

  read -r -p "nodelay [${KCP_NODELAY_DEFAULT}] (0/1): " KCP_NODELAY
  KCP_NODELAY="${KCP_NODELAY:-${KCP_NODELAY_DEFAULT}}"
  if [ "${KCP_NODELAY}" != "0" ] && [ "${KCP_NODELAY}" != "1" ]; then
    echo "nodelay must be 0 or 1." >&2
    exit 1
  fi

  read -r -p "interval [${KCP_INTERVAL_DEFAULT}] ms (10-5000): " KCP_INTERVAL
  KCP_INTERVAL="${KCP_INTERVAL:-${KCP_INTERVAL_DEFAULT}}"
  if ! is_number "${KCP_INTERVAL}" || [ "${KCP_INTERVAL}" -lt 10 ] || [ "${KCP_INTERVAL}" -gt 5000 ]; then
    echo "interval must be 10-5000." >&2
    exit 1
  fi

  read -r -p "resend [${KCP_RESEND_DEFAULT}] (0-2): " KCP_RESEND
  KCP_RESEND="${KCP_RESEND:-${KCP_RESEND_DEFAULT}}"
  if ! is_number "${KCP_RESEND}" || [ "${KCP_RESEND}" -lt 0 ] || [ "${KCP_RESEND}" -gt 2 ]; then
    echo "resend must be 0-2." >&2
    exit 1
  fi

  read -r -p "nocongestion [${KCP_NO_CONGESTION_DEFAULT}] (0/1): " KCP_NO_CONGESTION
  KCP_NO_CONGESTION="${KCP_NO_CONGESTION:-${KCP_NO_CONGESTION_DEFAULT}}"
  if [ "${KCP_NO_CONGESTION}" != "0" ] && [ "${KCP_NO_CONGESTION}" != "1" ]; then
    echo "nocongestion must be 0 or 1." >&2
    exit 1
  fi

  read -r -p "wdelay [${KCP_WDELAY_DEFAULT}] (true/false): " KCP_WDELAY
  KCP_WDELAY="${KCP_WDELAY:-${KCP_WDELAY_DEFAULT}}"
  if [ "${KCP_WDELAY}" != "true" ] && [ "${KCP_WDELAY}" != "false" ]; then
    echo "wdelay must be true or false." >&2
    exit 1
  fi

  read -r -p "acknodelay [${KCP_ACK_NODELAY_DEFAULT}] (true/false): " KCP_ACK_NODELAY
  KCP_ACK_NODELAY="${KCP_ACK_NODELAY:-${KCP_ACK_NODELAY_DEFAULT}}"
  if [ "${KCP_ACK_NODELAY}" != "true" ] && [ "${KCP_ACK_NODELAY}" != "false" ]; then
    echo "acknodelay must be true or false." >&2
    exit 1
  fi

  MANUAL_BLOCK=$(cat <<MANUAL
    nodelay: ${KCP_NODELAY}
    interval: ${KCP_INTERVAL}
    resend: ${KCP_RESEND}
    nocongestion: ${KCP_NO_CONGESTION}
    wdelay: ${KCP_WDELAY}
    acknodelay: ${KCP_ACK_NODELAY}
MANUAL
)
else
  KCP_NODELAY=""
  KCP_INTERVAL=""
  KCP_RESEND=""
  KCP_NO_CONGESTION=""
  KCP_WDELAY=""
  KCP_ACK_NODELAY=""
fi

read -r -p "KCP secret key [${KCP_KEY_DEFAULT}]: " KCP_KEY
KCP_KEY="${KCP_KEY:-${KCP_KEY_DEFAULT}}"
if [ -z "${KCP_KEY}" ]; then
  echo "KCP key is required. Copy it from server_info.txt." >&2
  exit 1
fi

mkdir -p "${PAQET_DIR}"

TMP_OUT="$(mktemp "${OUT_FILE}.tmp.XXXXXX")"
cat <<YAML > "${TMP_OUT}"
# paqet Client Configuration
role: "client"

log:
  level: "info"

socks5:
  - listen: "${SOCKS_LISTEN}"
    username: ""
    password: ""

network:
  interface: "${IFACE}"

  ipv4:
    addr: "${LOCAL_IP}:0"
    router_mac: "${GW_MAC}"

  tcp:
    local_flag: ["PA"]
    remote_flag: ["PA"]

server:
  addr: "${SERVER_IP}:${PORT}"

transport:
  protocol: "kcp"
  conn: ${KCP_CONN}

  kcp:
    mode: "${KCP_MODE}"
${MANUAL_BLOCK}    mtu: ${MTU}
    rcvwnd: ${KCP_RCVWND}
    sndwnd: ${KCP_SNDWND}
    key: "${KCP_KEY}"
YAML
mv "${TMP_OUT}" "${OUT_FILE}"

echo "Wrote ${OUT_FILE}"
