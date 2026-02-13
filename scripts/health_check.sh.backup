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

SERVICE_NAME="paqet-${ROLE}"
STATE_FILE="/var/tmp/paqet_health_${ROLE}.state"
MAX_RESTARTS_PER_HOUR=5
WINDOW_SEC=3600

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

prune_state() {
  if [ -f "${STATE_FILE}" ]; then
    awk -v now="$(date +%s)" -v win="${WINDOW_SEC}" '$1 >= (now-win)' "${STATE_FILE}" > "${STATE_FILE}.tmp" || true
    mv -f "${STATE_FILE}.tmp" "${STATE_FILE}"
  fi
}

record_restart() {
  date +%s >> "${STATE_FILE}"
}

restart_limit_reached() {
  prune_state
  local count=0
  if [ -f "${STATE_FILE}" ]; then
    count=$(wc -l < "${STATE_FILE}" | tr -d ' ')
  fi
  [ "${count}" -ge "${MAX_RESTARTS_PER_HOUR}" ]
}

restart_service() {
  if restart_limit_reached; then
    log "Restart limit reached (${MAX_RESTARTS_PER_HOUR}/hour). Skipping restart."
    exit 0
  fi
  log "Restarting ${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service" || true
  record_restart
}

# If service is not active, restart
if ! systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  log "Service not active."
  restart_service
  exit 0
fi

if [ "${ROLE}" = "client" ]; then
  # Client health check via SOCKS5
  CONFIG_FILE="${HOME}/paqet/client.yaml"
  SOCKS_LISTEN="127.0.0.1:1080"
  if [ -f "${CONFIG_FILE}" ]; then
    SOCKS_LISTEN="$(awk '
      $1 == "socks5:" { insocks=1; next }
      insocks && $1 == "-" && $2 == "listen:" { gsub(/"/, "", $3); print $3; exit }
      insocks && $1 == "listen:" { gsub(/"/, "", $2); print $2; exit }
    ' "${CONFIG_FILE}")"
    [ -z "${SOCKS_LISTEN}" ] && SOCKS_LISTEN="127.0.0.1:1080"
  fi

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL --connect-timeout 3 --max-time 6 https://httpbin.org/ip --proxy "socks5h://${SOCKS_LISTEN}" >/dev/null; then
      log "SOCKS test failed."
      restart_service
    fi
  else
    log "curl not available; skipping SOCKS test."
  fi

  exit 0
fi

# Server health check: recent log signals
if journalctl -u "${SERVICE_NAME}.service" --since "5 min ago" | grep -qiE "connection lost|timeout|reconnect"; then
  log "Detected connection issues in logs."
  restart_service
  exit 0
fi

# If no recent logs at all for 10 minutes, restart
if ! journalctl -u "${SERVICE_NAME}.service" --since "10 min ago" | grep -q .; then
  log "No recent logs for 10 minutes."
  restart_service
  exit 0
fi

exit 0
