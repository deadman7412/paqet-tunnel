#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
CLIENT_DIR="${ICMPTUNNEL_DIR}/client"
CONFIG_FILE="${CLIENT_DIR}/config.json"
INFO_FILE="${ICMPTUNNEL_DIR}/server_info.txt"

mkdir -p "${CLIENT_DIR}"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

read_info() {
  local file="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub($1"=",""); print; exit}' "${file}" 2>/dev/null || true
}

sync_ufw_icmp_rule_client() {
  local server_ip="$1"
  local socks_port="$2"
  local -a rules=()
  local do_install=""
  local do_enable=""
  local do_open=""
  local do_open_socks=""

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
        echo "[INFO] Setting default UFW policies..."
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        echo "[INFO] Allowing loopback interface..."
        ufw allow in on lo comment 'icmptunnel-loopback' >/dev/null 2>&1 || true

        echo "[INFO] Detecting and opening SSH ports..."
        local ssh_ports
        ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
        [ -z "${ssh_ports}" ] && ssh_ports="22"
        for p in ${ssh_ports}; do
          echo "[INFO] Opening SSH port ${p}..."
          ufw allow "${p}/tcp" comment 'ssh' >/dev/null 2>&1 || true
        done

        echo "[INFO] Enabling UFW..."
        ufw --force enable >/dev/null 2>&1 || true
        echo "[SUCCESS] UFW enabled successfully."
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  read -r -p "Allow outbound ICMP to ${server_ip} in UFW now? [Y/n]: " do_open
  case "${do_open:-Y}" in
    n|N|no|NO)
      echo "Skipped ICMP outbound rule."
      return 0
      ;;
  esac

  # Remove old icmptunnel rules
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/icmptunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi

  # Add outbound ICMP rule
  ufw allow out to "${server_ip}" proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
  echo "UFW: allowed outbound ICMP to ${server_ip}."

  # Open SOCKS5 service port for local users
  if [ -n "${socks_port}" ]; then
    read -r -p "Open SOCKS5 service port ${socks_port}/tcp for local users? [Y/n]: " do_open_socks
    case "${do_open_socks:-Y}" in
      n|N|no|NO)
        echo "Skipped opening SOCKS5 port."
        ;;
      *)
        # Remove existing icmptunnel-socks rules
        mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/icmptunnel-socks/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
        if [ "${#rules[@]}" -gt 0 ]; then
          for ((i=${#rules[@]}-1; i>=0; i--)); do
            ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
          done
        fi
        ufw allow "${socks_port}/tcp" comment 'icmptunnel-socks' >/dev/null 2>&1 || true
        echo "UFW: allowed inbound on SOCKS5 port tcp/${socks_port}."
        ;;
    esac
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

# Load defaults from server_info.txt if available
SERVER_IP_DEFAULT=""
API_PORT_DEFAULT="8080"
AUTH_KEY_DEFAULT=""
ENCRYPT_DATA_DEFAULT="true"
ENCRYPT_KEY_DEFAULT=""
DNS_SERVER_DEFAULT="8.8.8.8"
TIMEOUT_DEFAULT="20"

if [ -f "${INFO_FILE}" ]; then
  SERVER_IP_DEFAULT="$(read_info "${INFO_FILE}" "server_public_ip")"
  API_PORT_DEFAULT="$(read_info "${INFO_FILE}" "api_port")"
  AUTH_KEY_DEFAULT="$(read_info "${INFO_FILE}" "auth_key")"
  ENCRYPT_DATA_DEFAULT="$(read_info "${INFO_FILE}" "encrypt_data")"
  ENCRYPT_KEY_DEFAULT="$(read_info "${INFO_FILE}" "encrypt_data_key")"
  DNS_SERVER_DEFAULT="$(read_info "${INFO_FILE}" "dns_server")"
  TIMEOUT_DEFAULT="$(read_info "${INFO_FILE}" "timeout")"

  [ "${SERVER_IP_DEFAULT}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ] && SERVER_IP_DEFAULT=""
  [ -z "${API_PORT_DEFAULT}" ] && API_PORT_DEFAULT="8080"
  [ -z "${ENCRYPT_DATA_DEFAULT}" ] && ENCRYPT_DATA_DEFAULT="true"
  [ -z "${DNS_SERVER_DEFAULT}" ] && DNS_SERVER_DEFAULT="8.8.8.8"
  [ -z "${TIMEOUT_DEFAULT}" ] && TIMEOUT_DEFAULT="20"

  echo "Loaded defaults from ${INFO_FILE}"
fi

# Prompts
read -r -p "Server public IP [${SERVER_IP_DEFAULT}]: " SERVER_IP
SERVER_IP="${SERVER_IP:-${SERVER_IP_DEFAULT}}"
if [ -z "${SERVER_IP}" ]; then
  echo "Server public IP is required." >&2
  exit 1
fi

SOCKS_PORT_DEFAULT="1010"
read -r -p "SOCKS5 listen port [${SOCKS_PORT_DEFAULT}]: " SOCKS_PORT
SOCKS_PORT="${SOCKS_PORT:-${SOCKS_PORT_DEFAULT}}"
if ! validate_port "${SOCKS_PORT}"; then
  echo "Invalid SOCKS5 port: ${SOCKS_PORT}" >&2
  exit 1
fi

read -r -p "API port [${API_PORT_DEFAULT}]: " API_PORT
API_PORT="${API_PORT:-${API_PORT_DEFAULT}}"
if ! validate_port "${API_PORT}"; then
  echo "Invalid API port: ${API_PORT}" >&2
  exit 1
fi

read -r -p "Authentication key [${AUTH_KEY_DEFAULT}]: " AUTH_KEY
AUTH_KEY="${AUTH_KEY:-${AUTH_KEY_DEFAULT}}"
if [ -z "${AUTH_KEY}" ]; then
  echo "Authentication key is required." >&2
  exit 1
fi
if ! [[ "${AUTH_KEY}" =~ ^[0-9]+$ ]]; then
  echo "Authentication key must be numeric." >&2
  exit 1
fi

read -r -p "Enable encryption? [${ENCRYPT_DATA_DEFAULT}] (true/false): " ENCRYPT_DATA
ENCRYPT_DATA="${ENCRYPT_DATA:-${ENCRYPT_DATA_DEFAULT}}"
if [ "${ENCRYPT_DATA}" != "true" ] && [ "${ENCRYPT_DATA}" != "false" ]; then
  echo "encrypt_data must be true or false." >&2
  exit 1
fi

ENCRYPT_KEY=""
if [ "${ENCRYPT_DATA}" = "true" ]; then
  read -r -p "Encryption key [${ENCRYPT_KEY_DEFAULT}]: " ENCRYPT_KEY
  ENCRYPT_KEY="${ENCRYPT_KEY:-${ENCRYPT_KEY_DEFAULT}}"
  if [ -z "${ENCRYPT_KEY}" ]; then
    echo "Encryption key is required when encryption is enabled." >&2
    exit 1
  fi
fi

read -r -p "DNS server [${DNS_SERVER_DEFAULT}]: " DNS_SERVER
DNS_SERVER="${DNS_SERVER:-${DNS_SERVER_DEFAULT}}"

read -r -p "Connection timeout (seconds) [${TIMEOUT_DEFAULT}]: " TIMEOUT
TIMEOUT="${TIMEOUT:-${TIMEOUT_DEFAULT}}"

# Generate client config
cat > "${CONFIG_FILE}" <<EOF
{
  "type": "client",
  "listen_port_socks": "${SOCKS_PORT}",
  "server": "${SERVER_IP}",
  "timeout": ${TIMEOUT},
  "dns": "${DNS_SERVER}",
  "key": ${AUTH_KEY},
  "api_port": "${API_PORT}",
  "encrypt_data": ${ENCRYPT_DATA},
  "encrypt_data_key": "${ENCRYPT_KEY}"
}
EOF

echo "Wrote ${CONFIG_FILE}"
echo
echo "Using values:"
echo "  - server: ${SERVER_IP}"
echo "  - listen_port_socks: ${SOCKS_PORT}"
echo "  - api_port: ${API_PORT}"
echo "  - auth_key: ${AUTH_KEY}"
echo "  - encrypt_data: ${ENCRYPT_DATA}"
if [ -n "${ENCRYPT_KEY}" ]; then
  echo "  - encrypt_data_key: ${ENCRYPT_KEY}"
fi

sync_ufw_icmp_rule_client "${SERVER_IP}" "${SOCKS_PORT}"
