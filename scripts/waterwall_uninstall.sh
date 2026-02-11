#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
SERVICES=(
  "waterwall-direct-server"
  "waterwall-direct-client"
)

cleanup_services() {
  local svc unit
  for svc in "${SERVICES[@]}"; do
    unit="/etc/systemd/system/${svc}.service"
    systemctl stop "${svc}.service" 2>/dev/null || true
    systemctl disable "${svc}.service" 2>/dev/null || true
    systemctl reset-failed "${svc}.service" 2>/dev/null || true
    if [ -f "${unit}" ]; then
      rm -f "${unit}"
      echo "Removed service unit: ${unit}"
    fi
  done
  systemctl daemon-reload 2>/dev/null || true
}

if [ ! -d "${WATERWALL_DIR}" ]; then
  echo "Waterwall directory not found: ${WATERWALL_DIR}"
  echo "Cleaning Waterwall services only..."
  cleanup_services
  echo "Waterwall service cleanup completed."
  exit 0
fi

echo "This will remove: ${WATERWALL_DIR}"
echo "This will also remove Waterwall systemd services:"
for svc in "${SERVICES[@]}"; do
  echo "  - ${svc}.service"
done
read -r -p "Proceed with Waterwall uninstall? [y/N]: " confirm
case "${confirm}" in
  y|Y|yes|YES)
    cleanup_services
    rm -rf "${WATERWALL_DIR}"
    echo "Waterwall removed: ${WATERWALL_DIR}"
    echo "Waterwall services removed."
    ;;
  *)
    echo "Aborted."
    ;;
esac
