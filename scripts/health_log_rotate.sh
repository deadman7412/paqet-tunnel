#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-}"
MAX_SIZE_BYTES=$((1024*1024)) # 1MB

if [ -z "${LOG_FILE}" ]; then
  exit 0
fi

if [ -f "${LOG_FILE}" ]; then
  SIZE=$(wc -c < "${LOG_FILE}" | tr -d ' ')
  if [ "${SIZE}" -gt "${MAX_SIZE_BYTES}" ]; then
    mv -f "${LOG_FILE}" "${LOG_FILE}.1"
    : > "${LOG_FILE}"
  fi
fi
