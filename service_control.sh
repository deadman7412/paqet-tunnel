#!/usr/bin/env bash
set -euo pipefail

# Keep menu alive on Ctrl+C
trap 'echo; echo "Returning to menu...";' INT

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

while true; do
  echo
  echo "Service Control: ${SERVICE_NAME}"
  echo "1) Start"
  echo "2) Stop"
  echo "3) Restart"
  echo "4) Status"
  echo "5) Reset failed (clear failure state)"
  echo "6) Enable"
  echo "7) Disable"
  echo "8) Live logs (tail 20)"
  echo "0) Back"
  read -r -p "Select an option: " action

  case "${action}" in
    1) systemctl start "${SERVICE_NAME}.service" ;;
    2) systemctl stop "${SERVICE_NAME}.service" ;;
    3) systemctl restart "${SERVICE_NAME}.service" ;;
    4) systemctl status "${SERVICE_NAME}.service" --no-pager ;;
    5) systemctl reset-failed "${SERVICE_NAME}.service" ;;
    6) systemctl enable "${SERVICE_NAME}.service" ;;
    7) systemctl disable "${SERVICE_NAME}.service" ;;
    8) journalctl -u "${SERVICE_NAME}.service" -n 20 -f --no-pager ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2 ;;
  esac

done
