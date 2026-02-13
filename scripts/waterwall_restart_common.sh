#!/usr/bin/env bash
# Shared restart protection logic for WaterWall Tunnel
# Prevents infinite restart loops from health check and cron job conflicts

set -euo pipefail

# Configuration
COOLDOWN_SECONDS=120
MAX_RESTARTS_PER_HOUR=5
RESTART_WINDOW=3600
LOCK_TIMEOUT=10

# State file management
get_state_file() {
  local role="$1"
  echo "/var/tmp/waterwall_restart_state_${role}.txt"
}

get_lock_file() {
  local role="$1"
  echo "/var/tmp/waterwall_restart_${role}.lock"
}

# Logging
log_msg() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

# State management
prune_old_restarts() {
  local state_file="$1"
  local now
  now="$(date +%s)"
  local cutoff=$((now - RESTART_WINDOW))

  if [ -f "${state_file}" ]; then
    local tmp
    tmp="$(mktemp)"
    awk -v cutoff="${cutoff}" '$1 >= cutoff {print $0}' "${state_file}" > "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${state_file}"
  fi
}

record_restart() {
  local state_file="$1"
  local source="$2"
  local now
  now="$(date +%s)"

  echo "${now} ${source}" >> "${state_file}"
}

get_restart_count() {
  local state_file="$1"

  if [ ! -f "${state_file}" ]; then
    echo "0"
    return
  fi

  wc -l < "${state_file}" | tr -d ' '
}

get_last_restart_time() {
  local state_file="$1"

  if [ ! -f "${state_file}" ]; then
    echo "0"
    return
  fi

  tail -n 1 "${state_file}" 2>/dev/null | awk '{print $1}' || echo "0"
}

get_last_restart_source() {
  local state_file="$1"

  if [ ! -f "${state_file}" ]; then
    echo "none"
    return
  fi

  tail -n 1 "${state_file}" 2>/dev/null | awk '{print $2}' || echo "none"
}

# File locking
acquire_restart_lock() {
  local lock_file="$1"
  local timeout="${2:-${LOCK_TIMEOUT}}"

  exec 200>"${lock_file}"

  if ! flock -w "${timeout}" 200; then
    log_msg "ERROR: Could not acquire lock after ${timeout}s - another restart in progress"
    return 1
  fi

  return 0
}

release_restart_lock() {
  flock -u 200 2>/dev/null || true
}

# Restart permission check
check_restart_allowed() {
  local role="$1"
  local source="$2"
  local state_file
  state_file="$(get_state_file "${role}")"

  touch "${state_file}"
  prune_old_restarts "${state_file}"

  local count
  count="$(get_restart_count "${state_file}")"

  if [ "${count}" -ge "${MAX_RESTARTS_PER_HOUR}" ]; then
    log_msg "Restart DENIED: limit reached (${count}/${MAX_RESTARTS_PER_HOUR} per hour)"
    log_msg "ACTION REQUIRED: Check service health manually - automatic restarts stopped"
    return 1
  fi

  local last_restart
  last_restart="$(get_last_restart_time "${state_file}")"
  local last_source
  last_source="$(get_last_restart_source "${state_file}")"

  if [ "${last_restart}" != "0" ]; then
    local now
    now="$(date +%s)"
    local elapsed=$((now - last_restart))

    if [ "${elapsed}" -lt "${COOLDOWN_SECONDS}" ]; then
      local remaining=$((COOLDOWN_SECONDS - elapsed))
      log_msg "Restart SKIPPED: cooldown active (${elapsed}s ago by ${last_source}, need ${COOLDOWN_SECONDS}s, wait ${remaining}s more)"
      return 1
    fi
  fi

  log_msg "Restart ALLOWED: ${count} of ${MAX_RESTARTS_PER_HOUR} this hour, last restart ${last_restart} (${last_source})"
  return 0
}

# Service uptime check
get_service_uptime_seconds() {
  local service_name="$1"

  if ! systemctl is-active --quiet "${service_name}" 2>/dev/null; then
    echo "0"
    return
  fi

  local enter_ts
  enter_ts="$(systemctl show "${service_name}" --property=ActiveEnterTimestampMonotonic --value 2>/dev/null || echo "0")"

  if [ "${enter_ts}" = "0" ] || [ -z "${enter_ts}" ]; then
    echo "0"
    return
  fi

  local now_ts
  now_ts="$(date +%s%N | head -c 16)"

  local uptime_us=$((now_ts - enter_ts))
  local uptime_s=$((uptime_us / 1000000))

  echo "${uptime_s}"
}

# Safe restart function
safe_restart_service() {
  local role="$1"
  local source="$2"
  local service_name="waterwall-direct-${role}"
  local state_file
  state_file="$(get_state_file "${role}")"
  local lock_file
  lock_file="$(get_lock_file "${role}")"

  if ! acquire_restart_lock "${lock_file}"; then
    return 1
  fi

  if ! check_restart_allowed "${role}" "${source}"; then
    release_restart_lock
    return 1
  fi

  log_msg "Restarting ${service_name}.service (source: ${source})"

  if systemctl restart "${service_name}.service"; then
    log_msg "[SUCCESS] Service restarted successfully"
    record_restart "${state_file}" "${source}"
    release_restart_lock
    return 0
  else
    log_msg "[ERROR] Service restart failed"
    release_restart_lock
    return 1
  fi
}
