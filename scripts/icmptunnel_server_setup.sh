#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
SERVER_DIR="${ICMPTUNNEL_DIR}/server"
CONFIG_FILE="${SERVER_DIR}/config.json"
INFO_FILE="${ICMPTUNNEL_DIR}/server_info.txt"
INFO_FORMAT_VERSION="1"
CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${SERVER_DIR}"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -E "[:.]${p}$" >/dev/null 2>&1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -E "[:.]${p}$" >/dev/null 2>&1
  else
    return 1
  fi
}

random_port() {
  local p tries=0
  while :; do
    p="$(shuf -i 20000-60000 -n 1 2>/dev/null || true)"
    if [ -z "${p}" ]; then
      p="$(( (RANDOM % 40001) + 20000 ))"
    fi
    if ! port_in_use "${p}"; then
      echo "${p}"
      return 0
    fi
    tries=$((tries + 1))
    [ "${tries}" -lt 40 ] || break
  done
  echo "8080"
}

random_key() {
  local min="${1:-10000000}"
  local max="${2:-99999999}"
  echo "$(( RANDOM * RANDOM % (max - min + 1) + min ))"
}

rand_hex() {
  local n="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "${n}" 2>/dev/null | head -c "${n}"
  else
    head -c "${n}" /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c "${n}"
  fi
}

detect_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    ip="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(wget -qO- --timeout=5 https://ipinfo.io/ip 2>/dev/null || true)"
  fi
  echo "${ip}"
}

sync_ufw_icmp_rule_server() {
  local -a rules=()
  local do_install=""
  local do_enable=""
  local do_open=""
  local client_ip=""

  if ! command -v ufw >/dev/null 2>&1; then
    read -r -p "UFW is not installed. Install it now and configure ICMP firewall? [y/N]: " do_install
    case "${do_install}" in
      y|Y|yes|YES)
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -y
          DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
        elif command -v dnf >/dev/null 2>&1; then
          dnf install -y ufw
        elif command -v yum >/dev/null 2>&1; then
          yum install -y ufw
        else
          echo "No supported package manager found for UFW install." >&2
          return 0
        fi
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    read -r -p "UFW is installed but inactive. Enable UFW and configure ICMP now? [y/N]: " do_enable
    case "${do_enable}" in
      y|Y|yes|YES)
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow in on lo comment 'icmptunnel-loopback' >/dev/null 2>&1 || true

        # Detect SSH ports
        local ssh_ports
        ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
        [ -z "${ssh_ports}" ] && ssh_ports="22"
        for p in ${ssh_ports}; do
          ufw allow "${p}/tcp" comment 'ssh' >/dev/null 2>&1 || true
        done
        ufw --force enable >/dev/null 2>&1 || true
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  read -r -p "Configure ICMP firewall rules now? [Y/n]: " do_open
  case "${do_open:-Y}" in
    n|N|no|NO)
      echo "Skipped ICMP firewall configuration."
      return 0
      ;;
  esac

  echo
  echo "IMPORTANT: For security, ICMP tunnel should only accept connections from client IP."
  read -r -p "Enter client public IPv4 address (leave empty to allow from ANY IP): " client_ip

  # Remove old icmptunnel rules
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/icmptunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi

  # Add ICMP rule (protocol-based, not port-based)
  if [ -n "${client_ip}" ]; then
    ufw allow from "${client_ip}" proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
    echo "UFW: allowed inbound ICMP from ${client_ip} only."
  else
    echo "[WARN] No client IP provided. ICMP will be open to ALL IPs (not recommended)."
    ufw allow proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
    echo "UFW: allowed inbound ICMP from ANY IP."
  fi
}

if [ ! -x "${ICMPTUNNEL_DIR}/icmptunnel" ]; then
  echo "ICMP Tunnel binary not found: ${ICMPTUNNEL_DIR}/icmptunnel" >&2
  echo "Run 'Install ICMP Tunnel' first." >&2
  exit 1
fi

if [ -f "${CONFIG_FILE}" ]; then
  read -r -p "${CONFIG_FILE} exists. Overwrite? [y/N]: " ow
  case "${ow}" in
    y|Y) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# Prompts
API_PORT_DEFAULT="$(random_port)"
read -r -p "API port [${API_PORT_DEFAULT}]: " API_PORT
API_PORT="${API_PORT:-${API_PORT_DEFAULT}}"
if ! validate_port "${API_PORT}"; then
  echo "Invalid API port: ${API_PORT}" >&2
  exit 1
fi

AUTH_KEY_DEFAULT="$(random_key)"
read -r -p "Authentication key [${AUTH_KEY_DEFAULT}]: " AUTH_KEY
AUTH_KEY="${AUTH_KEY:-${AUTH_KEY_DEFAULT}}"
if ! [[ "${AUTH_KEY}" =~ ^[0-9]+$ ]]; then
  echo "Authentication key must be numeric." >&2
  exit 1
fi

read -r -p "Enable encryption? [Y/n]: " ENCRYPT_CHOICE
case "${ENCRYPT_CHOICE:-Y}" in
  n|N|no|NO) ENCRYPT_DATA="false"; ENCRYPT_KEY="" ;;
  *) ENCRYPT_DATA="true" ;;
esac

ENCRYPT_KEY=""
if [ "${ENCRYPT_DATA}" = "true" ]; then
  ENCRYPT_KEY_DEFAULT="$(rand_hex 16)"
  read -r -p "Encryption key [auto-generate]: " ENCRYPT_KEY
  ENCRYPT_KEY="${ENCRYPT_KEY:-${ENCRYPT_KEY_DEFAULT}}"
fi

DNS_SERVER_DEFAULT="8.8.8.8"
read -r -p "DNS server [${DNS_SERVER_DEFAULT}]: " DNS_SERVER
DNS_SERVER="${DNS_SERVER:-${DNS_SERVER_DEFAULT}}"

TIMEOUT_DEFAULT="20"
read -r -p "Connection timeout (seconds) [${TIMEOUT_DEFAULT}]: " TIMEOUT
TIMEOUT="${TIMEOUT:-${TIMEOUT_DEFAULT}}"

# Generate server config
cat > "${CONFIG_FILE}" <<EOF
{
  "type": "server",
  "listen_port_socks": "",
  "server": "",
  "timeout": ${TIMEOUT},
  "dns": "${DNS_SERVER}",
  "key": ${AUTH_KEY},
  "api_port": "${API_PORT}",
  "encrypt_data": ${ENCRYPT_DATA},
  "encrypt_data_key": "${ENCRYPT_KEY}"
}
EOF

echo "Wrote ${CONFIG_FILE}"

# Generate server_info.txt for client
SERVER_PUBLIC_IP="$(detect_public_ip)"
cat > "${INFO_FILE}" <<EOF
# Copy this file to the client VPS and place it at ${INFO_FILE}
format_version=${INFO_FORMAT_VERSION}
created_at=${CREATED_AT_UTC}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
api_port=${API_PORT}
auth_key=${AUTH_KEY}
encrypt_data=${ENCRYPT_DATA}
encrypt_data_key=${ENCRYPT_KEY}
dns_server=${DNS_SERVER}
timeout=${TIMEOUT}
EOF

echo "Wrote ${INFO_FILE}"
echo
echo "===== COPY/PASTE COMMANDS (CLIENT VPS) ====="
echo "mkdir -p ${ICMPTUNNEL_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo "============================================="
echo
echo "Generated values:"
echo "  - server_public_ip: ${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}"
echo "  - api_port: ${API_PORT}"
echo "  - auth_key: ${AUTH_KEY}"
echo "  - encrypt_data: ${ENCRYPT_DATA}"
if [ -n "${ENCRYPT_KEY}" ]; then
  echo "  - encrypt_data_key: ${ENCRYPT_KEY}"
fi

sync_ufw_icmp_rule_server
