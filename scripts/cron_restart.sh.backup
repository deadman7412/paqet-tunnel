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

CRON_FILE="/etc/cron.d/paqet-restart-${SERVICE_NAME}"

while true; do
  echo
  echo "Restart Scheduler: ${SERVICE_NAME}"
  echo "1) Every 30 minutes"
  echo "2) Every 1 hour"
  echo "3) Every 2 hours"
  echo "4) Every 4 hours"
  echo "5) Every 8 hours"
  echo "6) Every 12 hours"
  echo "7) Every 24 hours"
  echo "8) Remove scheduler"
  echo "0) Back"
  read -r -p "Select an option: " choice

  case "${choice}" in
    1) SCHEDULE="*/30 * * * *" ;;
    2) SCHEDULE="0 * * * *" ;;
    3) SCHEDULE="0 */2 * * *" ;;
    4) SCHEDULE="0 */4 * * *" ;;
    5) SCHEDULE="0 */8 * * *" ;;
    6) SCHEDULE="0 */12 * * *" ;;
    7) SCHEDULE="0 0 * * *" ;;
    8)
      if [ -f "${CRON_FILE}" ]; then
        rm -f "${CRON_FILE}"
        echo "Removed ${CRON_FILE}"
      else
        echo "No cron job found at ${CRON_FILE}"
      fi
      exit 0
      ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2; continue ;;
  esac

  cat <<CRON > "${CRON_FILE}"
${SCHEDULE} root /bin/systemctl restart ${SERVICE_NAME}.service
CRON
  chmod 644 "${CRON_FILE}"
  echo "Installed cron job: ${SCHEDULE}"
  exit 0

done
