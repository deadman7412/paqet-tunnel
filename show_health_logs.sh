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

LOG_FILE="/var/log/paqet-health-${ROLE}.log"

if [ ! -f "${LOG_FILE}" ]; then
  echo "Log file not found: ${LOG_FILE}" >&2
  exit 1
fi

while true; do
  echo
  echo "Health Log: ${LOG_FILE}"
  echo "1) Show last 100 lines"
  echo "2) Follow (tail -f)"
  echo "3) Clear log"
  echo "0) Back"
  read -r -p "Select an option: " choice

  case "${choice}" in
    1) tail -n 100 "${LOG_FILE}" ;;
    2) tail -n 100 -f "${LOG_FILE}" ;;
    3) : > "${LOG_FILE}"; echo "Cleared ${LOG_FILE}" ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2 ;;
  esac

done
