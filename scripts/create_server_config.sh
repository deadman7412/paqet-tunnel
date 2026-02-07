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
  if ! is_number "${PORT}"; then
    echo "Port must be a number." >&2
    exit 1
  fi
  if [ "${PORT}" -le 1024 ] || [ "${PORT}" -eq 80 ] || [ "${PORT}" -eq 443 ]; then
    echo "Avoid standard/low ports (e.g., 80/443). Use a high, non-standard port." >&2
    exit 1
  fi
fi

read -r -p "KCP mode [fast] (normal/fast/fast2/fast3/manual): " KCP_MODE
KCP_MODE="${KCP_MODE:-fast}"
if ! validate_mode "${KCP_MODE}"; then
  echo "Invalid KCP mode: ${KCP_MODE}" >&2
  exit 1
fi

read -r -p "KCP connections [1] (1-256): " KCP_CONN
KCP_CONN="${KCP_CONN:-1}"
if ! is_number "${KCP_CONN}" || [ "${KCP_CONN}" -lt 1 ] || [ "${KCP_CONN}" -gt 256 ]; then
  echo "KCP connections must be 1-256." >&2
  exit 1
fi

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [1350] (50-1500): " MTU
MTU="${MTU:-1350}"
if ! is_number "${MTU}" || [ "${MTU}" -lt 50 ] || [ "${MTU}" -gt 1500 ]; then
  echo "MTU must be 50-1500." >&2
  exit 1
fi

read -r -p "KCP receive window [1024]: " KCP_RCVWND
KCP_RCVWND="${KCP_RCVWND:-1024}"
if ! is_number "${KCP_RCVWND}" || [ "${KCP_RCVWND}" -lt 1 ]; then
  echo "KCP receive window must be a positive number." >&2
  exit 1
fi

read -r -p "KCP send window [1024]: " KCP_SNDWND
KCP_SNDWND="${KCP_SNDWND:-1024}"
if ! is_number "${KCP_SNDWND}" || [ "${KCP_SNDWND}" -lt 1 ]; then
  echo "KCP send window must be a positive number." >&2
  exit 1
fi

MANUAL_BLOCK=""
if [ "${KCP_MODE}" = "manual" ]; then
  echo "Manual mode selected. Set low-level KCP parameters."

  read -r -p "nodelay [1] (0/1): " KCP_NODELAY
  KCP_NODELAY="${KCP_NODELAY:-1}"
  if [ "${KCP_NODELAY}" != "0" ] && [ "${KCP_NODELAY}" != "1" ]; then
    echo "nodelay must be 0 or 1." >&2
    exit 1
  fi

  read -r -p "interval [10] ms (10-5000): " KCP_INTERVAL
  KCP_INTERVAL="${KCP_INTERVAL:-10}"
  if ! is_number "${KCP_INTERVAL}" || [ "${KCP_INTERVAL}" -lt 10 ] || [ "${KCP_INTERVAL}" -gt 5000 ]; then
    echo "interval must be 10-5000." >&2
    exit 1
  fi

  read -r -p "resend [2] (0-2): " KCP_RESEND
  KCP_RESEND="${KCP_RESEND:-2}"
  if ! is_number "${KCP_RESEND}" || [ "${KCP_RESEND}" -lt 0 ] || [ "${KCP_RESEND}" -gt 2 ]; then
    echo "resend must be 0-2." >&2
    exit 1
  fi

  read -r -p "nocongestion [1] (0/1): " KCP_NO_CONGESTION
  KCP_NO_CONGESTION="${KCP_NO_CONGESTION:-1}"
  if [ "${KCP_NO_CONGESTION}" != "0" ] && [ "${KCP_NO_CONGESTION}" != "1" ]; then
    echo "nocongestion must be 0 or 1." >&2
    exit 1
  fi

  read -r -p "wdelay [false] (true/false): " KCP_WDELAY
  KCP_WDELAY="${KCP_WDELAY:-false}"
  if [ "${KCP_WDELAY}" != "true" ] && [ "${KCP_WDELAY}" != "false" ]; then
    echo "wdelay must be true or false." >&2
    exit 1
  fi

  read -r -p "acknodelay [true] (true/false): " KCP_ACK_NODELAY
  KCP_ACK_NODELAY="${KCP_ACK_NODELAY:-true}"
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

read -r -p "KCP secret key (leave empty to auto-generate): " KCP_KEY
if [ -z "${KCP_KEY}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    KCP_KEY="$(openssl rand -hex 16)"
  else
    KCP_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  echo "Generated KCP key: ${KCP_KEY}"
fi

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

backup_file_if_exists "${INFO_FILE}"
TMP_INFO="$(mktemp "${INFO_FILE}.tmp.XXXXXX")"
cat <<INFO > "${TMP_INFO}"
# Copy this file to the client VPS and place it at ${INFO_FILE}
format_version=${INFO_FORMAT_VERSION}
created_at=${CREATED_AT_UTC}
listen_port=${PORT}
kcp_key=${KCP_KEY}
kcp_mode=${KCP_MODE}
kcp_conn=${KCP_CONN}
mtu=${MTU}
kcp_rcvwnd=${KCP_RCVWND}
kcp_sndwnd=${KCP_SNDWND}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
INFO
if [ "${KCP_MODE}" = "manual" ]; then
  {
    echo "kcp_nodelay=${KCP_NODELAY}"
    echo "kcp_interval=${KCP_INTERVAL}"
    echo "kcp_resend=${KCP_RESEND}"
    echo "kcp_nocongestion=${KCP_NO_CONGESTION}"
    echo "kcp_wdelay=${KCP_WDELAY}"
    echo "kcp_acknodelay=${KCP_ACK_NODELAY}"
  } >> "${TMP_INFO}"
fi
mv "${TMP_INFO}" "${INFO_FILE}"

echo "Wrote ${INFO_FILE}"
echo
echo "If you cannot transfer files, run these commands on the client VPS:"
echo "  mkdir -p ${PAQET_DIR}"
echo "  cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
if [ -z "${SERVER_PUBLIC_IP:-}" ]; then
  echo "Note: server_public_ip could not be detected. Update it manually."
fi
