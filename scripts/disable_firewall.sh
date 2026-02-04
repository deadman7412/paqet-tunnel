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

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed." >&2
  exit 0
fi

# Remove rules created by this script (by comment)
mapfile -t RULES < <(ufw status numbered | awk '/paqet-(tunnel|ssh)/ {gsub(/[\[\]]/,"",$1); print $1}')

if [ "${#RULES[@]}" -gt 0 ]; then
  # Delete from highest number to avoid reindex issues
  for ((i=${#RULES[@]}-1; i>=0; i--)); do
    ufw --force delete "${RULES[$i]}" || true
  done
fi

ufw disable
ufw status verbose
