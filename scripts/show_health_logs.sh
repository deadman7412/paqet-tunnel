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

YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "${LOG_FILE}" ]; then
  echo "Log file not found: ${LOG_FILE}" >&2
  exit 1
fi

trap 'echo; echo "Returning to menu...";' INT

while true; do
  echo
  echo "Health Log: ${LOG_FILE}"
  echo "1) Show last 100 lines"
  echo "2) Follow (tail -f)"
  echo "3) Clear log"
  echo "0) Back"
  read -r -p "Select an option: " choice

  case "${choice}" in
    1)
      if [ ! -s "${LOG_FILE}" ]; then
        echo
        echo -e "${YELLOW}No log entries yet.${NC}"
        echo
      else
        echo
        tail -n 100 "${LOG_FILE}"
        echo
      fi
      exit 0
      ;;
    2)
      echo
      echo "Press Ctrl+C to return to menu."
      echo
      tail -n 100 -f "${LOG_FILE}" || true
      exit 0
      ;;
    3)
      : > "${LOG_FILE}"
      echo
      echo "Cleared ${LOG_FILE}"
      echo
      exit 0
      ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2 ;;
  esac

done
