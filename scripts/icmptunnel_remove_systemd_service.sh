#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Role is required (server/client)." >&2
  exit 1
fi
case "${ROLE}" in
  server|client) ;;
  *) echo "Role must be server or client." >&2; exit 1 ;;
esac

SERVICE_NAME="icmptunnel-${ROLE}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"

if [ ! -f "${UNIT_PATH}" ]; then
  echo "Service not installed: ${SERVICE_NAME}" >&2
  exit 0
fi

echo "Stopping and removing ${SERVICE_NAME}..."

systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

rm -f "${UNIT_PATH}"
rm -rf "${DROPIN_DIR}"

systemctl daemon-reload
systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true

echo "${SERVICE_NAME} service removed."
