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

# Remove only tunnel rules; keep SSH rules to avoid lockout
mapfile -t RULES < <(ufw status numbered | awk '/paqet-tunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')

if [ "${#RULES[@]}" -gt 0 ]; then
  # Delete from highest number to avoid reindex issues
  for ((i=${#RULES[@]}-1; i>=0; i--)); do
    ufw --force delete "${RULES[$i]}" || true
  done
fi

ufw disable
ufw status verbose
