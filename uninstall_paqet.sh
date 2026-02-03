#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"

read -r -p "Remove paqet directory ${PAQET_DIR}? [y/N]: " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# Stop/disable known services if present
for svc in paqet-server paqet-client; do
  systemctl stop "${svc}.service" 2>/dev/null || true
  systemctl disable "${svc}.service" 2>/dev/null || true
  if [ -f "/etc/systemd/system/${svc}.service" ]; then
    rm -f "/etc/systemd/system/${svc}.service"
  fi
done
systemctl daemon-reload 2>/dev/null || true

# Remove cron jobs created by this menu
rm -f /etc/cron.d/paqet-restart-paqet-server /etc/cron.d/paqet-restart-paqet-client 2>/dev/null || true

# Remove paqet directory
rm -rf "${PAQET_DIR}"

echo "Uninstalled paqet from ${PAQET_DIR}"
