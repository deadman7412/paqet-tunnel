#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
BIN_PATH="${ICMPTUNNEL_DIR}/icmptunnel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/icmptunnel_install.sh"

if [ ! -f "${BIN_PATH}" ]; then
  echo "ICMP Tunnel is not installed at ${BIN_PATH}." >&2
  echo "Run 'Install ICMP Tunnel' first." >&2
  exit 1
fi

echo "Checking for updates..."

# Get current version info (file size/date as proxy since no version command)
CURRENT_SIZE="$(stat -c%s "${BIN_PATH}" 2>/dev/null || stat -f%z "${BIN_PATH}" 2>/dev/null || echo "0")"
CURRENT_DATE="$(stat -c%Y "${BIN_PATH}" 2>/dev/null || stat -f%m "${BIN_PATH}" 2>/dev/null || echo "0")"

echo "Current binary: ${CURRENT_SIZE} bytes (modified: $(date -d @"${CURRENT_DATE}" 2>/dev/null || date -r "${CURRENT_DATE}" 2>/dev/null || echo "unknown"))"

# Stop services before update
SERVER_SERVICE="icmptunnel-server"
CLIENT_SERVICE="icmptunnel-client"
SERVER_RUNNING="false"
CLIENT_RUNNING="false"

if systemctl is-active --quiet "${SERVER_SERVICE}.service" 2>/dev/null; then
  SERVER_RUNNING="true"
  echo "Stopping ${SERVER_SERVICE}..."
  systemctl stop "${SERVER_SERVICE}.service" || true
fi

if systemctl is-active --quiet "${CLIENT_SERVICE}.service" 2>/dev/null; then
  CLIENT_RUNNING="true"
  echo "Stopping ${CLIENT_SERVICE}..."
  systemctl stop "${CLIENT_SERVICE}.service" || true
fi

# Backup current binary
BACKUP_DIR="${ICMPTUNNEL_DIR}/backups"
mkdir -p "${BACKUP_DIR}"
BACKUP_FILE="${BACKUP_DIR}/icmptunnel.backup.$(date +%Y%m%d-%H%M%S)"
cp -f "${BIN_PATH}" "${BACKUP_FILE}"
echo "Backup created: ${BACKUP_FILE}"

# Run install script (will download latest)
if [ -x "${INSTALL_SCRIPT}" ]; then
  "${INSTALL_SCRIPT}"
else
  echo "Install script not found: ${INSTALL_SCRIPT}" >&2
  exit 1
fi

# Copy updated binary to /opt if WARP is enabled
if [ -d "/opt/icmptunnel" ]; then
  echo "Updating /opt/icmptunnel binary..."
  cp -f "${BIN_PATH}" "/opt/icmptunnel/icmptunnel"
  if id -u icmptunnel >/dev/null 2>&1; then
    chown root:icmptunnel "/opt/icmptunnel/icmptunnel" 2>/dev/null || true
    chmod 750 "/opt/icmptunnel/icmptunnel" || true
  fi
fi

# Restart services if they were running
if [ "${SERVER_RUNNING}" = "true" ]; then
  echo "Restarting ${SERVER_SERVICE}..."
  systemctl start "${SERVER_SERVICE}.service" || true
  systemctl status "${SERVER_SERVICE}.service" --no-pager || true
fi

if [ "${CLIENT_RUNNING}" = "true" ]; then
  echo "Restarting ${CLIENT_SERVICE}..."
  systemctl start "${CLIENT_SERVICE}.service" || true
  systemctl status "${CLIENT_SERVICE}.service" --no-pager || true
fi

NEW_SIZE="$(stat -c%s "${BIN_PATH}" 2>/dev/null || stat -f%z "${BIN_PATH}" 2>/dev/null || echo "0")"
echo
echo "Update complete."
echo "New binary: ${NEW_SIZE} bytes"
if [ "${CURRENT_SIZE}" = "${NEW_SIZE}" ]; then
  echo "Note: Binary size unchanged - you may already have the latest version."
fi
