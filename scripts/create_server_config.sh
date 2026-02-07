#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
OUT_FILE="${PAQET_DIR}/server.yaml"
INFO_FILE="${PAQET_DIR}/server_info.txt"
INFO_FORMAT_VERSION="1"
CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

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

if [ -f "${OUT_FILE}" ]; then
  read -r -p "${OUT_FILE} exists. Overwrite? [y/N]: " ow
  case "${ow}" in
    y|Y) backup_file_if_exists "${OUT_FILE}" ;;
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

random_port() {
  local port=""
  while true; do
    port="$(shuf -i 20000-60000 -n 1 2>/dev/null || awk 'BEGIN{srand(); print int(20000+rand()*40001)}')"
    if command -v ss >/dev/null 2>&1; then
      if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"; then
        echo "${port}"
        return
      fi
    else
      echo "${port}"
      return
    fi
  done
}

read -r -p "Listen port [random]: " PORT
if [ -z "${PORT}" ]; then
  PORT="$(random_port)"
  echo "Selected random port: ${PORT}"
else
  if ! [[ "${PORT}" =~ ^[0-9]+$ ]]; then
    echo "Port must be a number." >&2
    exit 1
  fi
  if [ "${PORT}" -le 1024 ] || [ "${PORT}" -eq 80 ] || [ "${PORT}" -eq 443 ]; then
    echo "Avoid standard/low ports (e.g., 80/443). Use a high, non-standard port." >&2
    exit 1
  fi
fi

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [1350]: " MTU
MTU="${MTU:-1350}"

read -r -p "KCP secret key (leave empty to auto-generate): " KCP_KEY
if [ -z "${KCP_KEY}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    KCP_KEY="$(openssl rand -hex 16)"
  else
    KCP_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  echo "Generated KCP key: ${KCP_KEY}"
fi

# Detect public IP (best-effort)
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
if [ -z "${SERVER_PUBLIC_IP}" ]; then
  if command -v curl >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ifconfig.me || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip || true)"
  elif command -v wget >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://api.ipify.org || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://ifconfig.me || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://ipinfo.io/ip || true)"
  fi
fi

mkdir -p "${PAQET_DIR}"

TMP_OUT="$(mktemp "${OUT_FILE}.tmp.XXXXXX")"
cat <<YAML > "${TMP_OUT}"
# paqet Server Configuration
role: "server"

log:
  level: "info"

listen:
  addr: ":${PORT}"

network:
  interface: "${IFACE}"

  ipv4:
    addr: "${LOCAL_IP}:${PORT}"
    router_mac: "${GW_MAC}"

  tcp:
    local_flag: ["PA"]

transport:
  protocol: "kcp"
  conn: 1

  kcp:
    mode: "fast"
    mtu: ${MTU}
    key: "${KCP_KEY}"
YAML
mv "${TMP_OUT}" "${OUT_FILE}"

echo "Wrote ${OUT_FILE}"

backup_file_if_exists "${INFO_FILE}"
TMP_INFO="$(mktemp "${INFO_FILE}.tmp.XXXXXX")"
cat <<INFO > "${TMP_INFO}"
# Copy this file to the client VPS and place it at ${INFO_FILE}
format_version=${INFO_FORMAT_VERSION}
created_at=${CREATED_AT_UTC}
listen_port=${PORT}
kcp_key=${KCP_KEY}
mtu=${MTU}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
INFO
mv "${TMP_INFO}" "${INFO_FILE}"

echo "Wrote ${INFO_FILE}"
echo
echo "If you cannot transfer files, run these commands on the client VPS:"
echo "  mkdir -p ${PAQET_DIR}"
echo "  cat <<'EOF' > ${INFO_FILE}"
echo "format_version=${INFO_FORMAT_VERSION}"
echo "created_at=${CREATED_AT_UTC}"
echo "listen_port=${PORT}"
echo "kcp_key=${KCP_KEY}"
echo "mtu=${MTU}"
echo "server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}"
echo "EOF"
if [ -z "${SERVER_PUBLIC_IP:-}" ]; then
  echo "Note: server_public_ip could not be detected. Update it manually." 
fi
