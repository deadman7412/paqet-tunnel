#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
case "${ROLE}" in
  server|client) ;;
  *) echo "Role is required (server/client)." >&2; exit 1 ;;
esac

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"
SERVER_CONFIG_FILE="${WATERWALL_DIR}/server/config.json"

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

remove_existing_waterwall_rules() {
  local -a rules=()
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/waterwall-tunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi
}

parse_server_port_from_config() {
  local config_file="$1"
  awk '
    /"type"[[:space:]]*:[[:space:]]*"TcpListener"/ { in_listener=1; next }
    in_listener && /"port"[[:space:]]*:[[:space:]]*[0-9]+/ {
      gsub(/[^0-9]/, "", $0);
      if ($0 != "") { print $0; exit }
    }
  ' "${config_file}" 2>/dev/null || true
}

parse_client_service_port_from_config() {
  local config_file="$1"
  python3 -c "
import json, sys
try:
    with open('${config_file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    if len(nodes) >= 1:
        listener = nodes[0].get('settings', {})
        port = listener.get('port', '')
        if port:
            print(port)
except:
    pass
" 2>/dev/null || true
}

ensure_ssh_rules() {
  local ssh_ports=""
  echo "[INFO] Detecting SSH ports..."

  # Detect SSH ports, suppress errors
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
ufw allow in on lo comment 'waterwall-loopback' >/dev/null 2>&1 || true
echo "[INFO] Ensuring SSH rules..."
ensure_ssh_rules
echo "[INFO] SSH rules configured."

echo "[INFO] Configuring firewall for role: ${ROLE}"

if [ "${ROLE}" = "server" ]; then
  LISTEN_PORT="$(read_info "${INFO_FILE}" "listen_port")"
  if [ -z "${LISTEN_PORT}" ] && [ -f "${SERVER_CONFIG_FILE}" ]; then
    LISTEN_PORT="$(parse_server_port_from_config "${SERVER_CONFIG_FILE}")"
  fi
  if [ -z "${LISTEN_PORT}" ]; then
    read -r -p "Waterwall server listen port (required): " LISTEN_PORT
  fi
  if [ -z "${LISTEN_PORT}" ]; then
    echo "Waterwall server port is required." >&2
    exit 1
  fi

  read -r -p "Waterwall client public IPv4 (required): " CLIENT_IP
  if [ -z "${CLIENT_IP}" ]; then
    echo "Client IP is required." >&2
    exit 1
  fi

  remove_existing_waterwall_rules
  ufw allow from "${CLIENT_IP}" to any port "${LISTEN_PORT}" proto tcp comment 'waterwall-tunnel' >/dev/null 2>&1 || true
  echo "Added UFW rule: allow ${CLIENT_IP} -> tcp/${LISTEN_PORT} (waterwall server)."
else
  echo "[INFO] Configuring client firewall..."
  CLIENT_CONFIG_FILE="${WATERWALL_DIR}/client/config.json"
  echo "[INFO] Checking for client config: ${CLIENT_CONFIG_FILE}"

  # Check if client config exists
  if [ ! -f "${CLIENT_CONFIG_FILE}" ]; then
    echo "[ERROR] Client config not found: ${CLIENT_CONFIG_FILE}" >&2
    echo "Run client setup first!" >&2
    exit 1
  fi
  echo "[INFO] Client config found."

  # Try to read from info file if it exists
  echo "[INFO] Checking for info file: ${INFO_FILE}"
  if [ -f "${INFO_FILE}" ]; then
    echo "[INFO] Info file found, reading values..."
    SERVER_IP="$(read_info "${INFO_FILE}" "server_public_ip")"
    SERVER_PORT="$(read_info "${INFO_FILE}" "listen_port")"
    SERVICE_PORT="$(read_info "${INFO_FILE}" "backend_port")"
    echo "[INFO] Read from info file - IP: ${SERVER_IP}, Port: ${SERVER_PORT}, Service: ${SERVICE_PORT}"
  else
    echo "[INFO] Info file not found, will parse from config."
    SERVER_IP=""
    SERVER_PORT=""
    SERVICE_PORT=""
  fi

  # Try to parse from client config if not in info file
  echo "[INFO] Parsing service port from client config..."
  if [ -z "${SERVICE_PORT}" ] && [ -f "${CLIENT_CONFIG_FILE}" ]; then
    SERVICE_PORT="$(parse_client_service_port_from_config "${CLIENT_CONFIG_FILE}")"
    echo "[INFO] Parsed service port: ${SERVICE_PORT}"
  fi

  # Parse server IP and port from client config as fallback
  echo "[INFO] Parsing server connection details from client config..."
  if [ -z "${SERVER_IP}" ] || [ -z "${SERVER_PORT}" ]; then
    eval "$(python3 -c "
import json
try:
    with open('${CLIENT_CONFIG_FILE}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    if len(nodes) >= 2:
        connector = nodes[1].get('settings', {})
        print('CONN_ADDR=' + str(connector.get('address', '')))
        print('CONN_PORT=' + str(connector.get('port', '')))
except:
    pass
" 2>/dev/null || echo "")"
    [ -z "${SERVER_IP}" ] && SERVER_IP="${CONN_ADDR}"
    [ -z "${SERVER_PORT}" ] && SERVER_PORT="${CONN_PORT}"
  fi

  if [ "${SERVER_IP}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
    SERVER_IP=""
  fi

  # Final check and prompt if still empty
  if [ -z "${SERVER_IP}" ]; then
    echo "[WARN] Could not auto-detect server IP from config"
    read -r -p "Waterwall server public IPv4 (required): " SERVER_IP
  fi
  if [ -z "${SERVER_PORT}" ]; then
    echo "[WARN] Could not auto-detect server port from config"
    read -r -p "Waterwall server listen port (required): " SERVER_PORT
  fi

  if [ -z "${SERVER_IP}" ] || [ -z "${SERVER_PORT}" ]; then
    echo "[ERROR] Server IP and server port are required." >&2
    exit 1
  fi

  echo "[INFO] Server IP: ${SERVER_IP}"
  echo "[INFO] Server port: ${SERVER_PORT}"
  if [ -n "${SERVICE_PORT}" ]; then
    echo "[INFO] Service port: ${SERVICE_PORT}"
  fi

  echo "[INFO] Removing existing waterwall rules..."
  remove_existing_waterwall_rules
  echo "[INFO] Adding outbound tunnel rule..."
  ufw allow out to "${SERVER_IP}" port "${SERVER_PORT}" proto tcp comment 'waterwall-tunnel' >/dev/null 2>&1 || true
  echo "[SUCCESS] Added UFW rule: allow out -> ${SERVER_IP}:${SERVER_PORT} (waterwall client)."

  # Open service port for local users/apps to connect (if provided)
  echo "[INFO] Checking if service port should be opened..."
  if [ -n "${SERVICE_PORT}" ]; then
    read -r -p "Open service port ${SERVICE_PORT}/tcp for local users? [Y/n]: " OPEN_SERVICE
    case "${OPEN_SERVICE:-Y}" in
      n|N|no|NO)
        echo "[INFO] Skipped opening service port."
        ;;
      *)
        echo "[INFO] Adding service port rule..."
        ufw allow "${SERVICE_PORT}/tcp" comment 'waterwall-service' >/dev/null 2>&1 || true
        echo "[SUCCESS] Added UFW rule: allow inbound -> tcp/${SERVICE_PORT} (waterwall service)."
        ;;
    esac
  else
    echo "[INFO] Service port not provided. Skipped opening service port in UFW."
    echo "You can open it manually later with: sudo ufw allow <SERVICE_PORT>/tcp"
  fi
fi

echo "[INFO] Enabling UFW..."
ufw --force enable
echo "[INFO] UFW enabled successfully."
echo "[INFO] Current UFW status:"
ufw status verbose
