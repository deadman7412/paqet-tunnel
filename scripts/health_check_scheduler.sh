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
CRON_FILE="/etc/cron.d/paqet-health-${SERVICE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/health_check.sh"
ROTATE_PATH="${SCRIPT_DIR}/health_log_rotate.sh"

while true; do
  echo
  echo "Health Check: ${SERVICE_NAME}"
  echo "1) Enable (every 2 minutes)"
  echo "2) Enable (every 5 minutes)"
  echo "3) Disable"
  echo "0) Back"
  read -r -p "Select an option: " choice

  case "${choice}" in
    1) SCHEDULE="*/2 * * * *" ;;
    2) SCHEDULE="*/5 * * * *" ;;
    3)
      if [ -f "${CRON_FILE}" ]; then
        rm -f "${CRON_FILE}"
        echo "Removed ${CRON_FILE}"
      else
        echo "No health check found at ${CRON_FILE}"
      fi
      exit 0
      ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2; continue ;;
  esac

  cat <<CRON > "${CRON_FILE}"
${SCHEDULE} root ${ROTATE_PATH} /var/log/paqet-health-${ROLE}.log
${SCHEDULE} root ${SCRIPT_PATH} ${ROLE} >> /var/log/paqet-health-${ROLE}.log 2>&1
CRON
  chmod 644 "${CRON_FILE}"
  echo "Installed health check: ${SCHEDULE}"
  exit 0

done
