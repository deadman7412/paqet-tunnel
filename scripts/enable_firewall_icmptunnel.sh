#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
case "${ROLE}" in
  server|client) ;;
  *) echo "Role is required (server/client)." >&2; exit 1 ;;
esac

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
INFO_FILE="${ICMPTUNNEL_DIR}/server_info.txt"
SERVER_CONFIG_FILE="${ICMPTUNNEL_DIR}/server/config.json"
CLIENT_CONFIG_FILE="${ICMPTUNNEL_DIR}/client/config.json"

ensure_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  read -r -p "ufw not found. Install ufw? [y/N]: " install_ufw
  case "${install_ufw}" in
    y|Y)
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ufw
      elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw
      else
        echo "No supported package manager found." >&2
        exit 1
      fi
      ;;
    *)
      echo "Skipped ufw install."
      exit 0
      ;;
  esac
}

read_info() {
  local file="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub($1"=",""); print; exit}' "${file}" 2>/dev/null || true
}

parse_socks_port_from_config() {
  local config_file="$1"
  python3 -c "
import json, sys
try:
    with open('${config_file}', 'r') as f:
        data = json.load(f)
    port = data.get('listen_port_socks', '')
    if port:
        print(port)
except:
    pass
" 2>/dev/null || true
}

remove_existing_icmptunnel_rules() {
  local -a rules=()
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/icmptunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi
}

ensure_ssh_rules() {
  local ssh_ports=""
  echo "[INFO] Detecting SSH ports..."

  ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"

  if [ -z "${ssh_ports}" ]; then
    echo "[INFO] No custom SSH ports found, using default port 22"
    ssh_ports="22"
  fi

  echo "[INFO] SSH ports detected: ${ssh_ports}"

  for p in ${ssh_ports}; do
    echo "[INFO] Checking SSH port ${p}..."
    if ! ufw status 2>/dev/null | grep -qE "\\b${p}/tcp\\b.*ALLOW IN"; then
      echo "[INFO] Opening SSH port ${p}..."
      ufw allow "${p}/tcp" comment 'ssh' >/dev/null 2>&1 || true
      echo "[INFO] SSH port ${p} opened"
    else
      echo "[INFO] SSH port ${p} already open"
    fi
  done
  echo "[INFO] SSH rules check complete"
}

echo "[INFO] Ensuring UFW is installed..."
ensure_ufw
echo "[INFO] Setting default policies..."
ufw default deny incoming
ufw default allow outgoing
echo "[INFO] Allowing loopback interface..."
ufw allow in on lo comment 'icmptunnel-loopback' >/dev/null 2>&1 || true
echo "[INFO] Ensuring SSH rules..."
ensure_ssh_rules
echo "[INFO] SSH rules configured."

echo "[INFO] Configuring firewall for role: ${ROLE}"

if [ "${ROLE}" = "server" ]; then
  CLIENT_IP=""

  # Try to read from info file or prompt
  if [ -f "${INFO_FILE}" ]; then
    echo "[INFO] Checking server_info.txt for client IP..."
  fi

  read -r -p "ICMP Tunnel client public IPv4 (leave empty to allow from ANY IP): " CLIENT_IP

  remove_existing_icmptunnel_rules

  # Add ICMP rule (protocol-based, not port-based)
  if [ -n "${CLIENT_IP}" ]; then
    ufw allow from "${CLIENT_IP}" proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
    echo "Added UFW rule: allow ${CLIENT_IP} -> ICMP (icmptunnel server)."
  else
    echo "[WARN] No client IP provided. ICMP will be open to ALL IPs."
    ufw allow proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
    echo "Added UFW rule: allow ICMP from ANY IP (icmptunnel server)."
  fi
else
  echo "[INFO] Configuring client firewall..."
  echo "[INFO] Checking for client config: ${CLIENT_CONFIG_FILE}"

  if [ ! -f "${CLIENT_CONFIG_FILE}" ]; then
    echo "[ERROR] Client config not found: ${CLIENT_CONFIG_FILE}" >&2
    echo "Run client setup first!" >&2
    exit 1
  fi
  echo "[INFO] Client config found."

  SERVER_IP=""
  SOCKS_PORT=""

  # Try to read from info file if it exists
  echo "[INFO] Checking for info file: ${INFO_FILE}"
  if [ -f "${INFO_FILE}" ]; then
    echo "[INFO] Info file found, reading values..."
    SERVER_IP="$(read_info "${INFO_FILE}" "server_public_ip")"
    echo "[INFO] Read from info file - IP: ${SERVER_IP}"
  else
    echo "[INFO] Info file not found."
  fi

  # Parse SOCKS port from client config
  echo "[INFO] Parsing SOCKS port from client config..."
  if [ -f "${CLIENT_CONFIG_FILE}" ]; then
    SOCKS_PORT="$(parse_socks_port_from_config "${CLIENT_CONFIG_FILE}")"
    echo "[INFO] Parsed SOCKS port: ${SOCKS_PORT}"
  fi

  # Parse server IP from client config as fallback
  if [ -z "${SERVER_IP}" ]; then
    echo "[INFO] Parsing server IP from client config..."
    eval "$(python3 -c "
import json
try:
    with open('${CLIENT_CONFIG_FILE}', 'r') as f:
        data = json.load(f)
    print('SERVER_IP=' + str(data.get('server', '')))
except:
    pass
" 2>/dev/null || echo "")"
  fi

  if [ "${SERVER_IP}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
    SERVER_IP=""
  fi

  # Final check and prompt if still empty
  if [ -z "${SERVER_IP}" ]; then
    echo "[WARN] Could not auto-detect server IP from config"
    read -r -p "ICMP Tunnel server public IPv4 (required): " SERVER_IP
  fi

  if [ -z "${SERVER_IP}" ]; then
    echo "[ERROR] Server IP is required." >&2
    exit 1
  fi

  echo "[INFO] Server IP: ${SERVER_IP}"
  if [ -n "${SOCKS_PORT}" ]; then
    echo "[INFO] SOCKS port: ${SOCKS_PORT}"
  fi

  echo "[INFO] Removing existing icmptunnel rules..."
  remove_existing_icmptunnel_rules
  echo "[INFO] Adding outbound ICMP rule..."
  ufw allow out to "${SERVER_IP}" proto icmp comment 'icmptunnel' >/dev/null 2>&1 || true
  echo "[SUCCESS] Added UFW rule: allow out -> ${SERVER_IP} ICMP (icmptunnel client)."

  # Open SOCKS port for local users/apps to connect (if provided)
  echo "[INFO] Checking if SOCKS port should be opened..."
  if [ -n "${SOCKS_PORT}" ]; then
    read -r -p "Open SOCKS5 port ${SOCKS_PORT}/tcp for local users? [Y/n]: " OPEN_SOCKS
    case "${OPEN_SOCKS:-Y}" in
      n|N|no|NO)
        echo "[INFO] Skipped opening SOCKS port."
        ;;
      *)
        echo "[INFO] Adding SOCKS port rule..."
        ufw allow "${SOCKS_PORT}/tcp" comment 'icmptunnel-socks' >/dev/null 2>&1 || true
        echo "[SUCCESS] Added UFW rule: allow inbound -> tcp/${SOCKS_PORT} (icmptunnel socks)."
        ;;
    esac
  else
    echo "[INFO] SOCKS port not provided. Skipped opening SOCKS port in UFW."
    echo "You can open it manually later with: sudo ufw allow <SOCKS_PORT>/tcp"
  fi
fi

echo "[INFO] Enabling UFW..."
ufw --force enable
echo "[INFO] UFW enabled successfully."
echo "[INFO] Current UFW status:"
ufw status verbose
