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

ensure_ssh_rules() {
  local ssh_ports=""
  ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
  if [ -z "${ssh_ports}" ]; then
    ssh_ports="22"
  fi

  echo "SSH ports detected: ${ssh_ports}"
  for p in ${ssh_ports}; do
    if ! ufw status 2>/dev/null | grep -qE "\\b${p}/tcp\\b.*ALLOW IN"; then
      ufw allow "${p}/tcp" comment 'waterwall-ssh' >/dev/null 2>&1 || true
    fi
  done
}

ensure_ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo comment 'waterwall-loopback' >/dev/null 2>&1 || true
ensure_ssh_rules

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
  SERVER_IP="$(read_info "${INFO_FILE}" "server_public_ip")"
  SERVER_PORT="$(read_info "${INFO_FILE}" "listen_port")"
  SERVICE_PORT="$(read_info "${INFO_FILE}" "backend_port")"
  if [ "${SERVER_IP}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
    SERVER_IP=""
  fi

  if [ -z "${SERVER_IP}" ]; then
    read -r -p "Waterwall server public IPv4 (required): " SERVER_IP
  fi
  if [ -z "${SERVER_PORT}" ]; then
    read -r -p "Waterwall server listen port (required): " SERVER_PORT
  fi
  if [ -z "${SERVICE_PORT}" ]; then
    read -r -p "Waterwall client service port (required): " SERVICE_PORT
  fi
  if [ -z "${SERVER_IP}" ] || [ -z "${SERVER_PORT}" ] || [ -z "${SERVICE_PORT}" ]; then
    echo "Server IP, server port, and service port are required." >&2
    exit 1
  fi

  remove_existing_waterwall_rules
  ufw allow out to "${SERVER_IP}" port "${SERVER_PORT}" proto tcp comment 'waterwall-tunnel' >/dev/null 2>&1 || true
  echo "Added UFW rule: allow out -> ${SERVER_IP}:${SERVER_PORT} (waterwall client)."

  # Open service port for local users/apps to connect
  read -r -p "Open service port ${SERVICE_PORT}/tcp for local users? [Y/n]: " OPEN_SERVICE
  case "${OPEN_SERVICE:-Y}" in
    n|N|no|NO)
      echo "Skipped opening service port."
      ;;
    *)
      ufw allow "${SERVICE_PORT}/tcp" comment 'waterwall-service' >/dev/null 2>&1 || true
      echo "Added UFW rule: allow inbound -> tcp/${SERVICE_PORT} (waterwall service)."
      ;;
  esac
fi

ufw --force enable
ufw status verbose
