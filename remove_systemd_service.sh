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

SERVICE_NAME="paqet-${ROLE}"

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
