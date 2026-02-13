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

if ! id -u icmptunnel >/dev/null 2>&1; then
  echo "icmptunnel user does not exist. WARP policy may not be enabled." >&2
  exit 0
fi

ICMPTUNNEL_UID="$(id -u icmptunnel)"

# Remove uidrange ip rules
echo "Removing uidrange ip rules..."
while ip rule show | grep -Eq "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}"; do
  ip rule del uidrange "${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" 2>/dev/null || true
done

echo "Note: No iptables cleanup needed (uidrange-only mode, SSH approach)."

# Remove systemd drop-in
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
WARP_DROPIN="${DROPIN_DIR}/10-warp.conf"

if [ -f "${WARP_DROPIN}" ]; then
  echo "Removing systemd drop-in: ${WARP_DROPIN}"
  rm -f "${WARP_DROPIN}"

  if [ -d "${DROPIN_DIR}" ] && [ -z "$(ls -A "${DROPIN_DIR}" 2>/dev/null)" ]; then
    rmdir "${DROPIN_DIR}"
  fi
fi

# Restore original service paths
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
if [ -f "${UNIT_PATH}" ]; then
  BIN_PATH="${ICMPTUNNEL_DIR}/icmptunnel"
  CONFIG_FILE="${ICMPTUNNEL_DIR}/${ROLE}/config.json"

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

  systemctl daemon-reload

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo "Restarting ${SERVICE_NAME}..."
    systemctl restart "${SERVICE_NAME}.service" || true
  fi
fi

# No iptables save needed (uidrange-only, no firewall changes)

set_state "icmptunnel_warp_enabled" "0"

echo "WARP binding disabled for ${SERVICE_NAME}."
