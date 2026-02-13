#!/usr/bin/env bash
set -euo pipefail

# === SETUP ===
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
CRON_FILE="/etc/cron.d/icmptunnel-health-${SERVICE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_CHECK_SCRIPT="${SCRIPT_DIR}/icmptunnel_health_check.sh"
LOG_ROTATE_SCRIPT="${SCRIPT_DIR}/icmptunnel_health_log_rotate.sh"
LOG_FILE="/var/log/icmptunnel-health-${ROLE}.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_current_status() {
  echo
  echo -e "${BLUE}Current Status:${NC}"

  if [ -f "${CRON_FILE}" ]; then
    echo -e "${GREEN}[ENABLED]${NC} Health check is active"
    echo "Cron file: ${CRON_FILE}"
    echo "Contents:"
    cat "${CRON_FILE}" | sed 's/^/  /'
  else
    echo "[DISABLED] Health check is not configured"
  fi

  if [ -f "${LOG_FILE}" ]; then
    echo
    echo "Recent log entries (last 5):"
    tail -n 5 "${LOG_FILE}" 2>/dev/null | sed 's/^/  /' || echo "  (no logs yet)"
  fi

  echo
}

while true; do
  show_current_status

  echo
  echo "========================================="
  echo "ICMP Tunnel Health Check: ${SERVICE_NAME}"
  echo "========================================="
  echo "1) Enable (check every 2 minutes)"
  echo "2) Enable (check every 5 minutes) - Recommended"
  echo "3) Enable (check every 10 minutes)"
  echo "4) Disable health check"
  echo "5) View full logs"
  echo "0) Back"
  echo
  read -r -p "Select an option: " choice

  case "${choice}" in
    1) SCHEDULE="*/2 * * * *"; DESCRIPTION="every 2 minutes" ;;
    2) SCHEDULE="*/5 * * * *"; DESCRIPTION="every 5 minutes" ;;
    3) SCHEDULE="*/10 * * * *"; DESCRIPTION="every 10 minutes" ;;
    4)
      if [ -f "${CRON_FILE}" ]; then
        rm -f "${CRON_FILE}"
        echo -e "${GREEN}[SUCCESS]${NC} Health check disabled"
        echo "Removed ${CRON_FILE}"
      else
        echo "[INFO] Health check was not enabled"
      fi
      read -r -p "Press Enter to continue..."
      continue
      ;;
    5)
      if [ -f "${LOG_FILE}" ]; then
        echo
        echo "=== Health Check Logs: ${LOG_FILE} ==="
        tail -n 50 "${LOG_FILE}" 2>/dev/null || echo "(no logs)"
        echo
      else
        echo "[INFO] Log file does not exist yet: ${LOG_FILE}"
      fi
      read -r -p "Press Enter to continue..."
      continue
      ;;
    0) exit 0 ;;
    *)
      echo "Invalid option." >&2
      read -r -p "Press Enter to continue..."
      continue
      ;;
  esac

  # Install health check
  echo
  echo "Installing health check: ${DESCRIPTION}"

  cat > "${CRON_FILE}" <<CRON
# ICMP Tunnel Health Check for ${SERVICE_NAME}
# Checks service health and restarts if needed (with protection against infinite loops)
${SCHEDULE} root ${LOG_ROTATE_SCRIPT} ${LOG_FILE} >> ${LOG_FILE} 2>&1
${SCHEDULE} root ${HEALTH_CHECK_SCRIPT} ${ROLE} >> ${LOG_FILE} 2>&1
CRON

  chmod 644 "${CRON_FILE}"

  echo -e "${GREEN}[SUCCESS]${NC} Health check installed: ${DESCRIPTION}"
  echo "Log file: ${LOG_FILE}"
  echo
  echo "Protection features enabled:"
  echo "  - Cooldown: 2 minutes between restarts"
  echo "  - Limit: Maximum 5 restarts per hour"
  echo "  - Retry: Tests 3 times before declaring failure"
  echo "  - Grace period: Waits 30s after service start before testing"
  echo
  echo "Monitor logs with: tail -f ${LOG_FILE}"

  read -r -p "Press Enter to continue..."
done
