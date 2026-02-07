#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"
INFO_FORMAT_VERSION="1"

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

  MTU="$(awk '
    $1 == "kcp:" { inkcp=1; next }
    inkcp && $1 == "mtu:" {
      gsub(/"/, "", $2);
      print $2;
      exit
    }
  ' "${CONFIG_FILE}")"
  [ -z "${MTU}" ] && MTU="1350"

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

  CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat <<INFO > "${INFO_FILE}"
# Copy this file to the client VPS and place it at ${INFO_FILE}
format_version=${INFO_FORMAT_VERSION}
created_at=${CREATED_AT_UTC}
listen_port=${PORT}
kcp_key=${KEY}
mtu=${MTU}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
INFO

  echo "Recreated ${INFO_FILE}"
fi

if grep -q "server_public_ip=REPLACE_WITH_SERVER_PUBLIC_IP" "${INFO_FILE}"; then
  # Try to auto-detect again
  AUTO_IP=""
  if command -v curl >/dev/null 2>&1; then
    AUTO_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org || true)"
    [ -z "${AUTO_IP}" ] && AUTO_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ifconfig.me || true)"
    [ -z "${AUTO_IP}" ] && AUTO_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip || true)"
  elif command -v wget >/dev/null 2>&1; then
    AUTO_IP="$(wget -qO- --timeout=5 https://api.ipify.org || true)"
    [ -z "${AUTO_IP}" ] && AUTO_IP="$(wget -qO- --timeout=5 https://ifconfig.me || true)"
    [ -z "${AUTO_IP}" ] && AUTO_IP="$(wget -qO- --timeout=5 https://ipinfo.io/ip || true)"
  fi

  if [ -n "${AUTO_IP}" ]; then
    sed -i "s/^server_public_ip=.*/server_public_ip=${AUTO_IP}/" "${INFO_FILE}"
    echo "Auto-detected server public IP: ${AUTO_IP}"
  else
    echo "Note: server_public_ip could not be detected."
    read -r -p "Enter server public IP (or leave empty to skip): " MANUAL_IP
    if [ -n "${MANUAL_IP}" ]; then
      sed -i "s/^server_public_ip=.*/server_public_ip=${MANUAL_IP}/" "${INFO_FILE}"
      echo "Updated server_public_ip in ${INFO_FILE}"
    else
      echo "Update it manually when ready."
    fi
  fi
fi

# Ensure mtu is present in existing file
if ! grep -q "^mtu=" "${INFO_FILE}"; then
  MTU_EXISTING="1350"
  if [ -f "${CONFIG_FILE}" ]; then
    MTU_EXISTING="$(awk '
      $1 == "kcp:" { inkcp=1; next }
      inkcp && $1 == "mtu:" { gsub(/\"/, \"\", $2); print $2; exit }
    ' "${CONFIG_FILE}")"
    [ -z "${MTU_EXISTING}" ] && MTU_EXISTING="1350"
  fi
  echo "mtu=${MTU_EXISTING}" >> "${INFO_FILE}"
fi

# Ensure metadata is present in existing file
if ! grep -q "^format_version=" "${INFO_FILE}"; then
  sed -i "1a format_version=${INFO_FORMAT_VERSION}" "${INFO_FILE}"
fi
if ! grep -q "^created_at=" "${INFO_FILE}"; then
  sed -i "1a created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${INFO_FILE}"
fi

echo
echo "=== ${INFO_FILE} ==="
echo
cat "${INFO_FILE}"
echo

echo
echo "===== COPY/PASTE COMMANDS (CLIENT VPS) ====="
echo "mkdir -p ${PAQET_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo "==========================================="
