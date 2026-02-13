#!/usr/bin/env bash
set -euo pipefail

# === SETUP ===
ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Usage: $0 {server|client}" >&2
  exit 1
fi

case "${ROLE}" in
  server|client) ;;
  *) echo "Invalid role. Must be server or client." >&2; exit 1 ;;
esac

SERVICE_NAME="paqet-${ROLE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared restart protection logic
# shellcheck source=scripts/paqet_restart_common.sh
source "${SCRIPT_DIR}/paqet_restart_common.sh"

# === MAIN LOGIC ===
main() {
  log_msg "=== Cron Restart Triggered: ${SERVICE_NAME} ==="

  # Check if service is running
  if ! systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    log_msg "Service is not active - systemd should auto-restart it"
    log_msg "Cron restart not needed"
    exit 0
  fi

  # Attempt smart restart (respects cooldown and limits)
  if safe_restart_service "${ROLE}" "cron"; then
    log_msg "=== Cron Restart Complete: Service restarted ==="
    exit 0
  else
    log_msg "=== Cron Restart Complete: Restart skipped (protection active) ==="
    exit 0
  fi
}

main
