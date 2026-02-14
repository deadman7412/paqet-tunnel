#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Role is required (server/client)." >&2
  exit 1
fi
case "${ROLE}" in
  server|client) ;;
  *) echo "Invalid role." >&2; exit 1 ;;
esac

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
CONFIG_FILE="${PAQET_DIR}/${ROLE}.yaml"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Config not found: ${CONFIG_FILE}" >&2
  echo "Create the ${ROLE} config first." >&2
  exit 1
fi

get_port_from_config() {
  local file="$1"
  local port=""
  if [ "${ROLE}" = "server" ]; then
    port="$(awk '
      $1 == "listen:" { inlisten=1; next }
      inlisten && $1 == "addr:" {
        gsub(/"/, "", $2);
        if ($2 ~ /:/) { sub(/^.*:/, "", $2); }
        print $2; exit
      }
    ' "${file}")"
  else
    port="$(awk '
      $1 == "server:" { inserver=1; next }
      inserver && $1 == "addr:" {
        gsub(/"/, "", $2);
        if ($2 ~ /:/) { sub(/^.*:/, "", $2); }
        print $2; exit
      }
    ' "${file}")"
  fi
  echo "${port}"
}

PORT="$(get_port_from_config "${CONFIG_FILE}")"
if [ -z "${PORT}" ]; then
  echo "Could not determine paqet port from ${CONFIG_FILE}." >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  read -r -p "ufw not found. Install ufw? [y/N]: " INSTALL_UFW
  case "${INSTALL_UFW}" in
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
    *) echo "Skipped ufw install."; exit 0 ;;
  esac
fi

# Set safe defaults
echo "[INFO] Setting UFW default policies..."
ufw default deny incoming
ufw default allow outgoing
echo "[INFO] Allowing loopback interface..."
ufw allow in on lo comment 'paqet-loopback' || true

# Detect SSH ports from sshd config - CRITICAL for preventing lockout
SSH_PORTS="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"
if [ -z "${SSH_PORTS}" ]; then
  SSH_PORTS="22"
fi

echo "[INFO] SSH ports detected: ${SSH_PORTS}"
echo "[INFO] Adding SSH allow rules to UFW (CRITICAL - prevents lockout)..."
for p in ${SSH_PORTS}; do
  if ! ufw status 2>/dev/null | grep -qE "\\b${p}/tcp\\b.*ALLOW IN"; then
    echo "[INFO] Opening SSH port ${p}/tcp..."
    ufw allow "${p}/tcp" comment 'paqet-ssh' || true
  else
    echo "[INFO] SSH port ${p}/tcp already open."
  fi
done
echo "[INFO] SSH protection configured."

if [ "${ROLE}" = "server" ]; then
  read -r -p "Client public IPv4 (required): " CLIENT_IP
  if [ -z "${CLIENT_IP}" ]; then
    echo "Client IP is required to restrict the paqet port." >&2
    exit 1
  fi
  if ! ufw status | grep -qE "${CLIENT_IP}.*${PORT}/tcp.*ALLOW IN"; then
    ufw allow from "${CLIENT_IP}" to any port "${PORT}" proto tcp comment 'paqet-tunnel' || true
  fi
else
  SERVER_IP=""
  INFO_FILE="${PAQET_DIR}/server_info.txt"
  if [ -f "${INFO_FILE}" ]; then
    SERVER_IP="$(awk -F= '/^server_public_ip=/{print $2; exit}' "${INFO_FILE}")"
    if [ "${SERVER_IP}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
      SERVER_IP=""
    fi
  fi
  if [ -z "${SERVER_IP}" ]; then
    read -r -p "Server public IPv4 (required): " SERVER_IP
  fi
  if [ -z "${SERVER_IP}" ]; then
    echo "Server IP is required to restrict the paqet port." >&2
    exit 1
  fi
  if ! ufw status | grep -qE "${SERVER_IP}.*${PORT}/tcp.*ALLOW OUT"; then
    ufw allow out to "${SERVER_IP}" port "${PORT}" proto tcp comment 'paqet-tunnel' || true
  fi
fi

echo "[INFO] Enabling UFW..."
ufw --force enable
echo "[INFO] UFW enabled successfully."
echo ""
echo "========================================"
echo "Firewall Configuration Complete"
echo "========================================"
echo ""
if [ "${ROLE}" = "server" ]; then
  echo "SERVER firewall configured for Paqet:"
  echo "  - SSH access: PROTECTED (ports: ${SSH_PORTS})"
  echo "  - Paqet tunnel: ALLOWED from ${CLIENT_IP} on port ${PORT}/tcp"
  echo "  - All other traffic: BLOCKED by default"
else
  echo "CLIENT firewall configured for Paqet:"
  echo "  - SSH access: PROTECTED (ports: ${SSH_PORTS})"
  echo "  - Outbound to server: ALLOWED to ${SERVER_IP}:${PORT}/tcp"
  echo "  - All other incoming: BLOCKED by default"
fi
echo ""
echo "========================================"
echo ""
ufw status verbose
