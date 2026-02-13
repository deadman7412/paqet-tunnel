#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Usage: $0 {server|client}" >&2
  exit 1
fi

case "${ROLE}" in
  server|client) ;;
  *) echo "Invalid role. Must be server or client." >&2; exit 1 ;;
esac

SERVICE_NAME="waterwall-direct-${ROLE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/waterwall_restart_common.sh
source "${SCRIPT_DIR}/waterwall_restart_common.sh"

main() {
  log_msg "=== Cron Restart Triggered: ${SERVICE_NAME} ==="

  if ! systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    log_msg "Service is not active - systemd should auto-restart it"
    log_msg "Cron restart not needed"
    exit 0
  fi

  if safe_restart_service "${ROLE}" "cron"; then
    log_msg "=== Cron Restart Complete: Service restarted ==="
    exit 0
  else
    log_msg "=== Cron Restart Complete: Restart skipped (protection active) ==="
    exit 0
  fi
}

main
