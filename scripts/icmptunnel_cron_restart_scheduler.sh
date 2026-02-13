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
CRON_FILE="/etc/cron.d/icmptunnel-restart-${SERVICE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTART_SCRIPT="${SCRIPT_DIR}/icmptunnel_cron_restart.sh"
LOG_FILE="/var/log/icmptunnel-cron-${ROLE}.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

show_current_status() {
  echo
  echo -e "${BLUE}Current Status:${NC}"

  if [ -f "${CRON_FILE}" ]; then
    echo -e "${GREEN}[ENABLED]${NC} Scheduled restart is active"
    echo "Cron file: ${CRON_FILE}"
    echo "Contents:"
    cat "${CRON_FILE}" | sed 's/^/  /'
  else
    echo "[DISABLED] Scheduled restart is not configured"
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
  echo "=============================================="
  echo "ICMP Tunnel Scheduled Restart: ${SERVICE_NAME}"
  echo "=============================================="
  echo "1) Every 10 minutes  [Aggressive - testing only]"
  echo "2) Every 30 minutes  [Frequent]"
  echo "3) Every 1 hour      [Balanced - Recommended]"
  echo "4) Every 2 hours     [Conservative]"
  echo "5) Every 4 hours     [Conservative]"
  echo "6) Every 6 hours     [Minimal]"
  echo "7) Every 12 hours    [Minimal]"
  echo "8) Every 24 hours    [Daily maintenance]"
  echo "9) Remove scheduler"
  echo "10) View full logs"
  echo "0) Back"
  echo
  read -r -p "Select an option: " choice

  case "${choice}" in
    1)
      SCHEDULE="*/10 * * * *"
      DESCRIPTION="every 10 minutes"
      echo
      echo -e "${YELLOW}[WARNING]${NC} Very frequent restarts can cause instability!"
      echo "This interval is only recommended for testing."
      read -r -p "Continue? [y/N]: " confirm
      case "${confirm}" in
        y|Y) ;;
        *) echo "Cancelled."; read -r -p "Press Enter to continue..."; continue ;;
      esac
      ;;
    2)
      SCHEDULE="*/30 * * * *"
      DESCRIPTION="every 30 minutes"
      echo
      echo -e "${YELLOW}[WARNING]${NC} Frequent restarts may impact stability."
      read -r -p "Continue? [y/N]: " confirm
      case "${confirm}" in
        y|Y) ;;
        *) echo "Cancelled."; read -r -p "Press Enter to continue..."; continue ;;
      esac
      ;;
    3) SCHEDULE="0 * * * *"; DESCRIPTION="every 1 hour" ;;
    4) SCHEDULE="0 */2 * * *"; DESCRIPTION="every 2 hours" ;;
    5) SCHEDULE="0 */4 * * *"; DESCRIPTION="every 4 hours" ;;
    6) SCHEDULE="0 */6 * * *"; DESCRIPTION="every 6 hours" ;;
    7) SCHEDULE="0 */12 * * *"; DESCRIPTION="every 12 hours" ;;
    8) SCHEDULE="0 0 * * *"; DESCRIPTION="every 24 hours (daily at midnight UTC)" ;;
    9)
      if [ -f "${CRON_FILE}" ]; then
        rm -f "${CRON_FILE}"
        echo -e "${GREEN}[SUCCESS]${NC} Scheduled restart disabled"
        echo "Removed ${CRON_FILE}"
      else
        echo "[INFO] Scheduled restart was not enabled"
      fi
      read -r -p "Press Enter to continue..."
      continue
      ;;
    10)
      if [ -f "${LOG_FILE}" ]; then
        echo
        echo "=== Cron Restart Logs: ${LOG_FILE} ==="
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

  # Install cron restart
  echo
  echo "Installing scheduled restart: ${DESCRIPTION}"

  cat > "${CRON_FILE}" <<CRON
# ICMP Tunnel Scheduled Restart for ${SERVICE_NAME}
# Smart restart with protection against infinite loops
${SCHEDULE} root ${RESTART_SCRIPT} ${ROLE} >> ${LOG_FILE} 2>&1
CRON

  chmod 644 "${CRON_FILE}"

  echo -e "${GREEN}[SUCCESS]${NC} Scheduled restart installed: ${DESCRIPTION}"
  echo "Log file: ${LOG_FILE}"
  echo
  echo "Protection features enabled:"
  echo "  - Cooldown: 2 minutes between restarts"
  echo "  - Limit: Maximum 5 restarts per hour"
  echo "  - Coordination: Respects health check restart limits"
  echo
  echo "Note: Restart will be skipped if:"
  echo "  - Service was restarted less than 2 minutes ago"
  echo "  - 5 restarts already happened in the last hour"
  echo "  - Another restart is already in progress"
  echo
  echo "Monitor logs with: tail -f ${LOG_FILE}"

  read -r -p "Press Enter to continue..."
done
