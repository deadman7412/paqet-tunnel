#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
SERVER_CFG="${PAQET_DIR}/server.yaml"
CLIENT_CFG="${PAQET_DIR}/client.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPAIR_SCRIPT="${SCRIPT_DIR}/repair_networking_stack.sh"

if [ ! -f "${SERVER_CFG}" ] && [ ! -f "${CLIENT_CFG}" ]; then
  echo "No server or client config found in ${PAQET_DIR}." >&2
  exit 1
fi

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [1350]: " MTU
MTU="${MTU:-1350}"

# Update server config if present
if [ -f "${SERVER_CFG}" ]; then
  if grep -q "^[[:space:]]*mtu:" "${SERVER_CFG}"; then
    sed -i "s/^[[:space:]]*mtu:.*/    mtu: ${MTU}/" "${SERVER_CFG}"
  else
    sed -i "/^[[:space:]]*kcp:/a\    mtu: ${MTU}" "${SERVER_CFG}"
  fi
  echo "Updated ${SERVER_CFG}"
fi

# Update client config if present
if [ -f "${CLIENT_CFG}" ]; then
  if grep -q "^[[:space:]]*mtu:" "${CLIENT_CFG}"; then
    sed -i "s/^[[:space:]]*mtu:.*/    mtu: ${MTU}/" "${CLIENT_CFG}"
  else
    sed -i "/^[[:space:]]*kcp:/a\    mtu: ${MTU}" "${CLIENT_CFG}"
  fi
  echo "Updated ${CLIENT_CFG}"
fi

# Update server_info.txt
if [ -f "${INFO_FILE}" ]; then
  if grep -q "^mtu=" "${INFO_FILE}"; then
    sed -i "s/^mtu=.*/mtu=${MTU}/" "${INFO_FILE}"
  else
    echo "mtu=${MTU}" >> "${INFO_FILE}"
  fi
  echo "Updated ${INFO_FILE}"
fi

echo "Restarting services to apply changes..."
if [ -f "${SERVER_CFG}" ]; then
  systemctl restart paqet-server.service 2>/dev/null || true
fi
if [ -f "${CLIENT_CFG}" ]; then
  systemctl restart paqet-client.service 2>/dev/null || true
fi

# Keep WARP MTU in sync (if enabled)
WGCF_CONF="/etc/wireguard/wgcf.conf"
if [ -f "${WGCF_CONF}" ]; then
  sed -i '/^MTU[[:space:]]*=.*/d' "${WGCF_CONF}"
  if grep -q '^\[Interface\]' "${WGCF_CONF}"; then
    sed -i "/^\\[Interface\\]/a MTU = ${MTU}" "${WGCF_CONF}"
    wg-quick down wgcf >/dev/null 2>&1 || true
    wg-quick up wgcf >/dev/null 2>&1 || true
    echo "WARP MTU set to ${MTU}"
  fi
fi

if [ -x "${REPAIR_SCRIPT}" ]; then
  read -r -p "Run networking repair now (recommended)? [Y/n]: " RUN_REPAIR
  case "${RUN_REPAIR}" in
    n|N)
      echo "Skipped networking repair."
      ;;
    *)
      "${REPAIR_SCRIPT}" auto || true
      ;;
  esac
fi

echo "Done."
