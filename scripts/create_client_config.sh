#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
OUT_FILE="${PAQET_DIR}/client.yaml"
INFO_FILE="${PAQET_DIR}/server_info.txt"

if [ -f "${OUT_FILE}" ]; then
  read -r -p "${OUT_FILE} exists. Overwrite? [y/N]: " ow
  case "${ow}" in
    y|Y) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# Detect defaults
IFACE_DEFAULT=""
if command -v ip >/dev/null 2>&1; then
  IFACE_DEFAULT="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
fi

read -r -p "Network interface [${IFACE_DEFAULT}]: " IFACE
IFACE="${IFACE:-${IFACE_DEFAULT}}"

LOCAL_IP_DEFAULT=""
if [ -n "${IFACE}" ] && command -v ip >/dev/null 2>&1; then
  LOCAL_IP_DEFAULT="$(ip -4 addr show dev "${IFACE}" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1)"
fi
read -r -p "Local IPv4 [${LOCAL_IP_DEFAULT}]: " LOCAL_IP
LOCAL_IP="${LOCAL_IP:-${LOCAL_IP_DEFAULT}}"

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

PORT_DEFAULT="9999"
KCP_KEY_DEFAULT=""
MTU_DEFAULT=""

if [ -f "${INFO_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${INFO_FILE}"
  if [ -n "${listen_port:-}" ]; then
    PORT_DEFAULT="${listen_port}"
  fi
  if [ -n "${kcp_key:-}" ]; then
    KCP_KEY_DEFAULT="${kcp_key}"
  fi
  if [ -n "${mtu:-}" ]; then
    MTU_DEFAULT="${mtu}"
  fi
  if [ -n "${server_public_ip:-}" ] && [ "${server_public_ip}" != "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
    SERVER_IP_DEFAULT="${server_public_ip}"
  else
    SERVER_IP_DEFAULT=""
  fi
  echo "Loaded defaults from ${INFO_FILE}"
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

read -r -p "SOCKS5 listen [127.0.0.1:1080]: " SOCKS_LISTEN
SOCKS_LISTEN="${SOCKS_LISTEN:-127.0.0.1:1080}"

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [${MTU_DEFAULT:-1350}]: " MTU
MTU="${MTU:-${MTU_DEFAULT:-1350}}"

read -r -p "KCP secret key [${KCP_KEY_DEFAULT}]: " KCP_KEY
KCP_KEY="${KCP_KEY:-${KCP_KEY_DEFAULT}}"
if [ -z "${KCP_KEY}" ]; then
  echo "KCP key is required. Copy it from server_info.txt." >&2
  exit 1
fi

mkdir -p "${PAQET_DIR}"

cat <<YAML > "${OUT_FILE}"
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
  conn: 1

  kcp:
    mode: "fast"
    mtu: ${MTU}
    key: "${KCP_KEY}"
YAML

echo "Wrote ${OUT_FILE}"
