#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

if [ ! -f "${INFO_FILE}" ]; then
  echo "Direct server info file not found: ${INFO_FILE}" >&2
  echo "Run: Waterwall Tunnel -> Direct Waterwall tunnel -> Server menu -> Server setup" >&2
  exit 1
fi

echo "===== WATERWALL DIRECT SERVER INFO ====="
cat "${INFO_FILE}"
echo "========================================"
echo
echo "===== COPY/PASTE COMMANDS (CLIENT VPS) ====="
echo "mkdir -p ${WATERWALL_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo "============================================="
