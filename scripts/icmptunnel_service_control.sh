#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
ACTION="${2:-}"

if [ -z "${ROLE}" ]; then
  echo "Usage: $0 {server|client} {start|stop|restart|status|logs|enable|disable}" >&2
  exit 1
fi

case "${ROLE}" in
  server|client) ;;
  *)
    echo "Invalid role: ${ROLE}" >&2
    echo "Usage: $0 {server|client} {start|stop|restart|status|logs|enable|disable}" >&2
    exit 1
    ;;
esac

SERVICE_NAME="icmptunnel-${ROLE}"

if [ -z "${ACTION}" ]; then
  echo "Available actions:"
  echo "  start   - Start the service"
  echo "  stop    - Stop the service"
  echo "  restart - Restart the service"
  echo "  status  - Show service status"
  echo "  logs    - Show service logs"
  echo "  enable  - Enable service to start on boot"
  echo "  disable - Disable service from starting on boot"
  echo
  read -r -p "Select action: " ACTION
fi

case "${ACTION}" in
  start)
    systemctl start "${SERVICE_NAME}.service"
    systemctl status "${SERVICE_NAME}.service" --no-pager
    ;;
  stop)
    systemctl stop "${SERVICE_NAME}.service"
    systemctl status "${SERVICE_NAME}.service" --no-pager || true
    ;;
  restart)
    systemctl restart "${SERVICE_NAME}.service"
    systemctl status "${SERVICE_NAME}.service" --no-pager
    ;;
  status)
    systemctl status "${SERVICE_NAME}.service" --no-pager || true
    ;;
  logs)
    journalctl -u "${SERVICE_NAME}.service" -n 100 --no-pager
    ;;
  enable)
    systemctl enable "${SERVICE_NAME}.service"
    echo "${SERVICE_NAME} enabled to start on boot."
    ;;
  disable)
    systemctl disable "${SERVICE_NAME}.service"
    echo "${SERVICE_NAME} disabled from starting on boot."
    ;;
  *)
    echo "Invalid action: ${ACTION}" >&2
    echo "Usage: $0 {server|client} {start|stop|restart|status|logs|enable|disable}" >&2
    exit 1
    ;;
esac
