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

# Detect SSH ports from sshd config
SSH_PORTS="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
if [ -z "${SSH_PORTS}" ]; then
  SSH_PORTS="22"
fi

for p in ${SSH_PORTS}; do
  ufw allow "${p}/tcp" comment 'paqet-ssh' || true
done

if [ "${ROLE}" = "server" ]; then
  read -r -p "Client public IPv4 (required): " CLIENT_IP
  if [ -z "${CLIENT_IP}" ]; then
    echo "Client IP is required to restrict the paqet port." >&2
    exit 1
  fi
  ufw allow from "${CLIENT_IP}" to any port "${PORT}" proto tcp comment 'paqet-tunnel' || true
else
  SERVER_IP=""
  INFO_FILE="${PAQET_DIR}/server_info.txt"
  if [ -f "${INFO_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${INFO_FILE}"
    if [ -n "${server_public_ip:-}" ] && [ "${server_public_ip}" != "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
      SERVER_IP="${server_public_ip}"
    fi
  fi
  if [ -z "${SERVER_IP}" ]; then
    read -r -p "Server public IPv4 (required): " SERVER_IP
  fi
  if [ -z "${SERVER_IP}" ]; then
    echo "Server IP is required to restrict the paqet port." >&2
    exit 1
  fi
  ufw allow out to "${SERVER_IP}" port "${PORT}" proto tcp comment 'paqet-tunnel' || true
fi

ufw --force enable
ufw status verbose
