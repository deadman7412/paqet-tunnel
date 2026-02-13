#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="icmptunnel-${ROLE}"
ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
ICMPTUNNEL_POLICY_STATE_DIR="/etc/icmptunnel-policy"
ICMPTUNNEL_POLICY_STATE_FILE="${ICMPTUNNEL_POLICY_STATE_DIR}/settings.env"

TABLE_ID=51820

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${ICMPTUNNEL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${ICMPTUNNEL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${ICMPTUNNEL_POLICY_STATE_FILE}"
  chmod 600 "${ICMPTUNNEL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "========================================="
echo "ICMP Tunnel WARP Policy - Disable"
echo "========================================="
echo "[DEBUG] Role: ${ROLE}"
echo "[DEBUG] Service: ${SERVICE_NAME}"
echo

echo "[DEBUG] Checking icmptunnel user..."
if ! id -u icmptunnel >/dev/null 2>&1; then
  echo "[INFO] icmptunnel user does not exist. WARP policy may not be enabled." >&2
  exit 0
fi

ICMPTUNNEL_UID="$(id -u icmptunnel)"
echo "[DEBUG] icmptunnel UID: ${ICMPTUNNEL_UID}"

# Remove uidrange ip rules
echo
echo "[INFO] Removing uidrange ip rules..."
echo "[DEBUG] Rules to remove (before cleanup):"
ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (none found)"

RULES_REMOVED=0
while ip rule show | grep -Eq "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}"; do
  echo "[DEBUG] Deleting uidrange rule..."
  if ip rule del uidrange "${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" 2>&1 | sed 's/^/  /'; then
    RULES_REMOVED=$((RULES_REMOVED + 1))
  fi
done

echo "[INFO] Removed ${RULES_REMOVED} uidrange rule(s)"
echo "[DEBUG] Remaining uidrange rules (after cleanup):"
ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (none - good!)"

echo
echo "[INFO] No iptables cleanup needed (uidrange-only mode, SSH approach)."

# Remove systemd drop-in
echo
echo "[DEBUG] Checking systemd drop-in configuration..."
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
WARP_DROPIN="${DROPIN_DIR}/10-warp.conf"

if [ -f "${WARP_DROPIN}" ]; then
  echo "[INFO] Removing systemd drop-in: ${WARP_DROPIN}"
  rm -f "${WARP_DROPIN}"
  echo "[SUCCESS] Drop-in removed"

  if [ -d "${DROPIN_DIR}" ] && [ -z "$(ls -A "${DROPIN_DIR}" 2>/dev/null)" ]; then
    echo "[DEBUG] Drop-in directory is empty, removing..."
    rmdir "${DROPIN_DIR}"
    echo "[SUCCESS] Drop-in directory removed"
  fi
else
  echo "[DEBUG] No WARP drop-in found at ${WARP_DROPIN}"
fi

# Restore original service paths
echo
echo "[DEBUG] Restoring original service configuration..."
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
if [ -f "${UNIT_PATH}" ]; then
  BIN_PATH="${ICMPTUNNEL_DIR}/icmptunnel"
  CONFIG_FILE="${ICMPTUNNEL_DIR}/${ROLE}/config.json"

  echo "[INFO] Writing restored service file: ${UNIT_PATH}"
  cat > "${UNIT_PATH}" <<EOF
[Unit]
Description=ICMP Tunnel ${ROLE} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$(dirname "${CONFIG_FILE}")
ExecStart=${BIN_PATH}
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  echo "[SUCCESS] Service file restored"

  echo "[INFO] Reloading systemd daemon..."
  systemctl daemon-reload

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo "[INFO] Restarting ${SERVICE_NAME}..."
    if systemctl restart "${SERVICE_NAME}.service"; then
      echo "[SUCCESS] Service restarted successfully"
    else
      echo "[WARN] Service restart failed" >&2
    fi
  else
    echo "[DEBUG] Service is not running, skipping restart"
  fi
else
  echo "[DEBUG] Service file not found: ${UNIT_PATH}"
fi

# No iptables save needed (uidrange-only, no firewall changes)

set_state "icmptunnel_warp_enabled" "0"

echo
echo "========================================="
echo "[SUCCESS] WARP binding disabled for ${SERVICE_NAME}"
echo "========================================="
echo
echo "[DEBUG] Final verification:"
echo "[DEBUG] Remaining uidrange rules for UID ${ICMPTUNNEL_UID}:"
ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (none - good!)"
echo
echo "[DEBUG] Service status:"
systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -n 10 | sed 's/^/  /' || echo "  (service not running)"
echo "========================================="
