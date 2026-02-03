#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"

if [ ! -f "${INFO_FILE}" ]; then
  echo "${INFO_FILE} not found. Attempting to recreate..."

  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Server config not found: ${CONFIG_FILE}" >&2
    exit 1
  fi

  PORT="$(awk '
    $1 == "listen:" { inlisten=1; next }
    inlisten && $1 == "addr:" {
      gsub(/"/, "", $2);
      sub(/^:/, "", $2);
      print $2;
      exit
    }
  ' "${CONFIG_FILE}")"

  KEY="$(awk '
    $1 == "kcp:" { inkcp=1; next }
    inkcp && $1 == "key:" {
      gsub(/"/, "", $2);
      print $2;
      exit
    }
  ' "${CONFIG_FILE}")"

  SERVER_PUBLIC_IP=""
  if command -v curl >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ifconfig.me || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip || true)"
  elif command -v wget >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://api.ipify.org || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://ifconfig.me || true)"
    [ -z "${SERVER_PUBLIC_IP}" ] && SERVER_PUBLIC_IP="$(wget -qO- --timeout=5 https://ipinfo.io/ip || true)"
  fi

  if [ -z "${PORT}" ] || [ -z "${KEY}" ]; then
    echo "Could not extract listen port or kcp key from ${CONFIG_FILE}." >&2
    exit 1
  fi

  cat <<INFO > "${INFO_FILE}"
# Copy this file to the client VPS and place it at ${INFO_FILE}
listen_port=${PORT}
kcp_key=${KEY}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
INFO

  echo "Recreated ${INFO_FILE}"
fi

echo "=== ${INFO_FILE} ==="
echo
cat "${INFO_FILE}"
echo
echo "===== COPY/PASTE COMMANDS (CLIENT VPS) ====="
echo "mkdir -p ${PAQET_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo "==========================================="
if grep -q "server_public_ip=REPLACE_WITH_SERVER_PUBLIC_IP" "${INFO_FILE}"; then
  echo "Note: server_public_ip could not be detected. Update it manually."
fi
