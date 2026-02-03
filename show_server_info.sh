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
    SERVER_PUBLIC_IP="$(curl -fsS https://api.ipify.org || true)"
  elif command -v wget >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(wget -qO- https://api.ipify.org || true)"
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

echo "--- ${INFO_FILE} ---"
cat "${INFO_FILE}"
echo
echo "If you cannot transfer files, run these commands on the client VPS:"
echo "  mkdir -p ${PAQET_DIR}"
echo "  cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
