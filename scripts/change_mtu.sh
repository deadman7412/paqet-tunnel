#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
SERVER_CFG="${PAQET_DIR}/server.yaml"
CLIENT_CFG="${PAQET_DIR}/client.yaml"

if [ ! -f "${SERVER_CFG}" ]; then
  echo "Server config not found: ${SERVER_CFG}" >&2
  exit 1
fi

echo "MTU affects packet fragmentation. If you see SSL errors, try 1200."
read -r -p "MTU [1350]: " MTU
MTU="${MTU:-1350}"

# Update server config
if grep -q "^[[:space:]]*mtu:" "${SERVER_CFG}"; then
  sed -i "s/^[[:space:]]*mtu:.*/    mtu: ${MTU}/" "${SERVER_CFG}"
else
  sed -i "/^[[:space:]]*kcp:/a\    mtu: ${MTU}" "${SERVER_CFG}"
fi

echo "Updated ${SERVER_CFG}"

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

echo "Done. Restart services to apply changes."
