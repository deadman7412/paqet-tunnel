#!/usr/bin/env bash
set -euo pipefail

ROLE=""
read -r -p "Role (server/client, or leave empty to enter service name): " ROLE
SERVICE_NAME=""

case "${ROLE}" in
  server|client)
    SERVICE_NAME="paqet-${ROLE}"
    ;;
  "")
    read -r -p "Service name (e.g., paqet-server): " SERVICE_NAME
    ;;
  *)
    echo "Invalid role." >&2
    exit 1
    ;;
esac

if [ -z "${SERVICE_NAME}" ]; then
  echo "Service name is required." >&2
  exit 1
fi

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

if [ -f "${UNIT_PATH}" ]; then
  rm -f "${UNIT_PATH}"
  systemctl daemon-reload
  echo "Removed ${UNIT_PATH}"
else
  echo "Service file not found: ${UNIT_PATH}" >&2
fi
