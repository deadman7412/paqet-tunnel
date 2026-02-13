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

SERVICE_NAME="icmptunnel-${ROLE}"
ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared restart protection logic
# shellcheck source=scripts/icmptunnel_restart_common.sh
source "${SCRIPT_DIR}/icmptunnel_restart_common.sh"

# === HEALTH CHECK CONFIGURATION ===
HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_RETRY_DELAY=5
GRACE_PERIOD_SECONDS=30  # Don't test service for this long after start

# === HEALTH CHECK TESTS ===
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

test_client_socks_proxy() {
  local config_file="${ICMPTUNNEL_DIR}/client/config.json"

  if [ ! -f "${config_file}" ]; then
    log_msg "Health check ERROR: Client config not found: ${config_file}"
    return 1
  fi

  # Parse SOCKS port from config
  local socks_port
  socks_port="$(python3 -c "
import json
try:
    with open('${config_file}', 'r') as f:
        data = json.load(f)
    print(data.get('listen_port_socks', ''))
except:
    pass
" 2>/dev/null || echo "")"

  if [ -z "${socks_port}" ]; then
    log_msg "Health check ERROR: Could not parse SOCKS port from config"
    return 1
  fi

  # Check if SOCKS proxy is listening
  if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${socks_port}$" >/dev/null 2>&1; then
    log_msg "Health check FAIL: SOCKS proxy not listening on port ${socks_port}"
    return 1
  fi

  # Test SOCKS proxy with curl
  if ! command -v curl >/dev/null 2>&1; then
    log_msg "Health check WARN: curl not available, skipping SOCKS test"
    return 0  # Don't fail if curl is missing
  fi

  local test_url="https://httpbin.org/ip"
  if curl -fsSL --connect-timeout 3 --max-time 6 --proxy "socks5h://127.0.0.1:${socks_port}" "${test_url}" >/dev/null 2>&1; then
    log_msg "Health check PASS: SOCKS proxy test successful (port ${socks_port})"
    return 0
  else
    log_msg "Health check FAIL: SOCKS proxy test failed (port ${socks_port}, url ${test_url})"
    return 1
  fi
}

test_server_logs() {
  # Check journalctl for error patterns
  if ! command -v journalctl >/dev/null 2>&1; then
    log_msg "Health check WARN: journalctl not available, skipping log check"
    return 0
  fi

  # Check last 5 minutes of logs for error patterns
  if journalctl -u "${SERVICE_NAME}.service" --since "5 min ago" 2>/dev/null | grep -qiE "connection lost|timeout|unreachable|fatal|panic|error.*tunnel"; then
    log_msg "Health check FAIL: Detected errors in recent logs"
    return 1
  fi

  # Check if there are any logs at all in last 10 minutes (service might be stuck)
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

# === MAIN HEALTH CHECK LOGIC ===
main() {
  log_msg "=== Health Check Start: ${SERVICE_NAME} ==="

  # Step 1: Check if service is active
  if ! test_service_active; then
    log_msg "Service is not active - systemd should auto-restart (Restart=on-failure)"
    log_msg "No manual restart needed"
    exit 0
  fi

  # Step 2: Check grace period
  if ! test_grace_period; then
    # Too soon after start, skip health check
    exit 0
  fi

  # Step 3: Role-specific health tests
  local health_failed=0

  if [ "${ROLE}" = "client" ]; then
    log_msg "Running client health check (SOCKS proxy test)..."
    if ! run_health_check_with_retry test_client_socks_proxy; then
      health_failed=1
    fi
  else
    # Server role
    log_msg "Running server health check (log analysis)..."
    if ! run_health_check_with_retry test_server_logs; then
      health_failed=1
    fi
  fi

  # Step 4: Decide if restart is needed
  if [ ${health_failed} -eq 0 ]; then
    log_msg "=== Health Check PASSED: Service is healthy ==="
    exit 0
  fi

  # Health check failed - attempt restart
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
