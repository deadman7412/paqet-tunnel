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

SERVICE_NAME="icmptunnel-${ROLE}"

# Check if service exists
if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
  echo "Service not installed: ${SERVICE_NAME}" >&2
  exit 1
fi

while true; do
  echo
  echo "Service Logs: ${SERVICE_NAME}"
  echo "1) Last 50 lines"
  echo "2) Last 100 lines"
  echo "3) Last 200 lines"
  echo "4) Live logs (tail 20, follow)"
  echo "0) Back"
  read -r -p "Select an option: " action

  case "${action}" in
    1) journalctl -u "${SERVICE_NAME}.service" -n 50 --no-pager ;;
    2) journalctl -u "${SERVICE_NAME}.service" -n 100 --no-pager ;;
    3) journalctl -u "${SERVICE_NAME}.service" -n 200 --no-pager ;;
    4)
      echo
      echo "Press Ctrl+C to return to menu."
      echo
      journalctl -u "${SERVICE_NAME}.service" -n 20 -f --no-pager || true
      ;;
    0) exit 0 ;;
    *) echo "Invalid option." >&2 ;;
  esac

done
