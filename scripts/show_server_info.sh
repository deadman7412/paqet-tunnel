#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"
INFO_FORMAT_VERSION="1"

get_kcp_field() {
  local field="$1"
  awk -v key="${field}" '
    $1 == "kcp:" { inkcp=1; next }
    inkcp && $0 ~ /^  [a-zA-Z_]+:/ { inkcp=0 }
    inkcp && $1 == key":" {
      gsub(/"/, "", $2)
      print $2
      exit
    }
  ' "${CONFIG_FILE}"
}

get_transport_conn() {
  awk '
    $1 == "transport:" { intransport=1; next }
    intransport && $1 ~ /^[a-zA-Z_]/ && $1 != "conn:" && $1 != "kcp:" && $1 != "protocol:" { intransport=0 }
    intransport && $1 == "conn:" { print $2; exit }
  ' "${CONFIG_FILE}"
}

if [ ! -f "${INFO_FILE}" ]; then
  echo "${INFO_FILE} not found. Attempting to recreate..."

  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Server config not found: ${CONFIG_FILE}" >&2
    exit 1
  fi

  PORT="$(awk '
    $1 == "listen:" { inlisten=1; next }
    inlisten && $1 == "addr:" {
      gsub(/"/, "", $2)
      sub(/^:/, "", $2)
      print $2
      exit
    }
  ' "${CONFIG_FILE}")"

  KEY="$(get_kcp_field key)"
  MTU="$(get_kcp_field mtu)"
  KCP_MODE="$(get_kcp_field mode)"
  KCP_CONN="$(get_transport_conn)"
  KCP_RCVWND="$(get_kcp_field rcvwnd)"
  KCP_SNDWND="$(get_kcp_field sndwnd)"

  KCP_NODELAY="$(get_kcp_field nodelay)"
  KCP_INTERVAL="$(get_kcp_field interval)"
  KCP_RESEND="$(get_kcp_field resend)"
  KCP_NO_CONGESTION="$(get_kcp_field nocongestion)"
  KCP_WDELAY="$(get_kcp_field wdelay)"
  KCP_ACK_NODELAY="$(get_kcp_field acknodelay)"

  [ -z "${MTU}" ] && MTU="1350"
  [ -z "${KCP_MODE}" ] && KCP_MODE="fast"
  [ -z "${KCP_CONN}" ] && KCP_CONN="1"
  [ -z "${KCP_RCVWND}" ] && KCP_RCVWND="1024"
  [ -z "${KCP_SNDWND}" ] && KCP_SNDWND="1024"

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
kcp_mode=${KCP_MODE}
kcp_conn=${KCP_CONN}
mtu=${MTU}
kcp_rcvwnd=${KCP_RCVWND}
kcp_sndwnd=${KCP_SNDWND}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
INFO

  if [ "${KCP_MODE}" = "manual" ]; then
    {
      echo "kcp_nodelay=${KCP_NODELAY:-1}"
      echo "kcp_interval=${KCP_INTERVAL:-10}"
      echo "kcp_resend=${KCP_RESEND:-2}"
      echo "kcp_nocongestion=${KCP_NO_CONGESTION:-1}"
      echo "kcp_wdelay=${KCP_WDELAY:-false}"
      echo "kcp_acknodelay=${KCP_ACK_NODELAY:-true}"
    } >> "${INFO_FILE}"
  fi

  echo "Recreated ${INFO_FILE}"
fi

if grep -q "server_public_ip=REPLACE_WITH_SERVER_PUBLIC_IP" "${INFO_FILE}"; then
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

if [ -f "${CONFIG_FILE}" ]; then
  PORT_EXISTING="$(awk '
    $1 == "listen:" { inlisten=1; next }
    inlisten && $1 == "addr:" {
      gsub(/"/, "", $2)
      sub(/^:/, "", $2)
      print $2
      exit
    }
  ' "${CONFIG_FILE}")"
  KEY_EXISTING="$(get_kcp_field key)"
  MTU_EXISTING="$(get_kcp_field mtu)"
  MODE_EXISTING="$(get_kcp_field mode)"
  CONN_EXISTING="$(get_transport_conn)"
  RCVWND_EXISTING="$(get_kcp_field rcvwnd)"
  SNDWND_EXISTING="$(get_kcp_field sndwnd)"

  [ -z "${MTU_EXISTING}" ] && MTU_EXISTING="1350"
  [ -z "${MODE_EXISTING}" ] && MODE_EXISTING="fast"
  [ -z "${CONN_EXISTING}" ] && CONN_EXISTING="1"
  [ -z "${RCVWND_EXISTING}" ] && RCVWND_EXISTING="1024"
  [ -z "${SNDWND_EXISTING}" ] && SNDWND_EXISTING="1024"

  grep -q '^listen_port=' "${INFO_FILE}" || echo "listen_port=${PORT_EXISTING}" >> "${INFO_FILE}"
  grep -q '^kcp_key=' "${INFO_FILE}" || echo "kcp_key=${KEY_EXISTING}" >> "${INFO_FILE}"
  grep -q '^mtu=' "${INFO_FILE}" || echo "mtu=${MTU_EXISTING}" >> "${INFO_FILE}"
  grep -q '^kcp_mode=' "${INFO_FILE}" || echo "kcp_mode=${MODE_EXISTING}" >> "${INFO_FILE}"
  grep -q '^kcp_conn=' "${INFO_FILE}" || echo "kcp_conn=${CONN_EXISTING}" >> "${INFO_FILE}"
  grep -q '^kcp_rcvwnd=' "${INFO_FILE}" || echo "kcp_rcvwnd=${RCVWND_EXISTING}" >> "${INFO_FILE}"
  grep -q '^kcp_sndwnd=' "${INFO_FILE}" || echo "kcp_sndwnd=${SNDWND_EXISTING}" >> "${INFO_FILE}"

  if [ "${MODE_EXISTING}" = "manual" ]; then
    NODELAY_EXISTING="$(get_kcp_field nodelay)"
    INTERVAL_EXISTING="$(get_kcp_field interval)"
    RESEND_EXISTING="$(get_kcp_field resend)"
    NOCONG_EXISTING="$(get_kcp_field nocongestion)"
    WDELAY_EXISTING="$(get_kcp_field wdelay)"
    ACKNODELAY_EXISTING="$(get_kcp_field acknodelay)"

    grep -q '^kcp_nodelay=' "${INFO_FILE}" || echo "kcp_nodelay=${NODELAY_EXISTING:-1}" >> "${INFO_FILE}"
    grep -q '^kcp_interval=' "${INFO_FILE}" || echo "kcp_interval=${INTERVAL_EXISTING:-10}" >> "${INFO_FILE}"
    grep -q '^kcp_resend=' "${INFO_FILE}" || echo "kcp_resend=${RESEND_EXISTING:-2}" >> "${INFO_FILE}"
    grep -q '^kcp_nocongestion=' "${INFO_FILE}" || echo "kcp_nocongestion=${NOCONG_EXISTING:-1}" >> "${INFO_FILE}"
    grep -q '^kcp_wdelay=' "${INFO_FILE}" || echo "kcp_wdelay=${WDELAY_EXISTING:-false}" >> "${INFO_FILE}"
    grep -q '^kcp_acknodelay=' "${INFO_FILE}" || echo "kcp_acknodelay=${ACKNODELAY_EXISTING:-true}" >> "${INFO_FILE}"
  fi
fi

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
