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
WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/waterwall_restart_common.sh
source "${SCRIPT_DIR}/waterwall_restart_common.sh"

HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_RETRY_DELAY=5
GRACE_PERIOD_SECONDS=30

# Health check tests
test_service_active() {
  if ! systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    log_msg "Health check: Service is NOT active"
    return 1
  fi
  log_msg "Health check: Service is active"
  return 0
}

test_grace_period() {
  local uptime
  uptime="$(get_service_uptime_seconds "${SERVICE_NAME}.service")"

  if [ "${uptime}" -lt "${GRACE_PERIOD_SECONDS}" ]; then
    log_msg "Health check SKIPPED: Service recently started (${uptime}s ago, grace period ${GRACE_PERIOD_SECONDS}s)"
    return 1
  fi

  log_msg "Health check: Grace period passed (uptime: ${uptime}s)"
  return 0
}

test_client_tcp_listener() {
  local config_file="${WATERWALL_DIR}/client/config.json"

  if [ ! -f "${config_file}" ]; then
    log_msg "Health check ERROR: Client config not found: ${config_file}"
    return 1
  fi

  # Parse listen port from config
  local listen_port
  listen_port="$(python3 -c "
import json
try:
    with open('${config_file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    if nodes:
        listener = nodes[0].get('settings', {})
        print(listener.get('port', ''))
except:
    pass
" 2>/dev/null || echo "")"

  if [ -z "${listen_port}" ]; then
    log_msg "Health check ERROR: Could not parse listen port from config"
    return 1
  fi

  # Check if port is listening
  if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${listen_port}$" >/dev/null 2>&1; then
    log_msg "Health check FAIL: TCP listener not active on port ${listen_port}"
    return 1
  fi

  log_msg "Health check PASS: TCP listener active on port ${listen_port}"
  return 0
}

test_server_logs() {
  if ! command -v journalctl >/dev/null 2>&1; then
    log_msg "Health check WARN: journalctl not available, skipping log check"
    return 0
  fi

  if journalctl -u "${SERVICE_NAME}.service" --since "5 min ago" 2>/dev/null | grep -qiE "error|fatal|panic|failed|timeout"; then
    log_msg "Health check FAIL: Detected errors in recent logs"
    return 1
  fi

  if ! journalctl -u "${SERVICE_NAME}.service" --since "10 min ago" 2>/dev/null | grep -q .; then
    log_msg "Health check WARN: No logs in last 10 minutes (service might be stuck)"
    return 1
  fi

  log_msg "Health check PASS: Server logs look healthy"
  return 0
}

run_health_check_with_retry() {
  local attempts=0
  local test_func="$1"

  while [ ${attempts} -lt ${HEALTH_CHECK_RETRIES} ]; do
    attempts=$((attempts + 1))

    if ${test_func}; then
      return 0
    fi

    if [ ${attempts} -lt ${HEALTH_CHECK_RETRIES} ]; then
      log_msg "Health check: Retry ${attempts}/${HEALTH_CHECK_RETRIES} after ${HEALTH_CHECK_RETRY_DELAY}s"
      sleep ${HEALTH_CHECK_RETRY_DELAY}
    fi
  done

  log_msg "Health check FAILED: All ${HEALTH_CHECK_RETRIES} attempts failed"
  return 1
}

# Main logic
main() {
  log_msg "=== Health Check Start: ${SERVICE_NAME} ==="

  if ! test_service_active; then
    log_msg "Service is not active - systemd should auto-restart (Restart=on-failure)"
    log_msg "No manual restart needed"
    exit 0
  fi

  if ! test_grace_period; then
    exit 0
  fi

  local health_failed=0

  if [ "${ROLE}" = "client" ]; then
    log_msg "Running client health check (TCP listener test)..."
    if ! run_health_check_with_retry test_client_tcp_listener; then
      health_failed=1
    fi
  else
    log_msg "Running server health check (log analysis)..."
    if ! run_health_check_with_retry test_server_logs; then
      health_failed=1
    fi
  fi

  if [ ${health_failed} -eq 0 ]; then
    log_msg "=== Health Check PASSED: Service is healthy ==="
    exit 0
  fi

  log_msg "=== Health Check FAILED: Restart needed ==="

  if safe_restart_service "${ROLE}" "health"; then
    log_msg "=== Health Check Complete: Service restarted ==="
    exit 0
  else
    log_msg "=== Health Check Complete: Restart skipped (protection active) ==="
    exit 0
  fi
}

main
