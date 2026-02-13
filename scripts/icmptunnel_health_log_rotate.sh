#!/usr/bin/env bash
set -euo pipefail

# Simple log rotation for ICMP Tunnel health check logs
# Keeps logs manageable to prevent disk space issues

LOG_FILE="${1:-}"
MAX_LINES=10000

if [ -z "${LOG_FILE}" ]; then
  echo "Usage: $0 <log_file>" >&2
  exit 1
fi

if [ ! -f "${LOG_FILE}" ]; then
  # Log file doesn't exist yet, nothing to rotate
  exit 0
fi

# Count lines
line_count=$(wc -l < "${LOG_FILE}" 2>/dev/null | tr -d ' ')

if [ "${line_count}" -gt "${MAX_LINES}" ]; then
  # Keep last 5000 lines, discard older ones
  tail -n 5000 "${LOG_FILE}" > "${LOG_FILE}.tmp"
  mv -f "${LOG_FILE}.tmp" "${LOG_FILE}"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Log rotated: ${line_count} lines -> 5000 lines" >> "${LOG_FILE}"
fi

exit 0
