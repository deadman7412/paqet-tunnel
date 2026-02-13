#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Role is required (server/client)." >&2
  exit 1
fi
case "${ROLE}" in
  server|client) ;;
  *) echo "Role must be server or client." >&2; exit 1 ;;
esac

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
ROLE_DIR="${ICMPTUNNEL_DIR}/${ROLE}"
BIN_PATH="${ICMPTUNNEL_DIR}/icmptunnel"
CONFIG_FILE="${ROLE_DIR}/config.json"
SERVICE_NAME="icmptunnel-${ROLE}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

if [ ! -x "${BIN_PATH}" ]; then
  if [ -f "${BIN_PATH}" ]; then
    chmod +x "${BIN_PATH}" || true
  fi
fi

if [ ! -x "${BIN_PATH}" ]; then
  echo "ICMP Tunnel binary not found or not executable: ${BIN_PATH}" >&2
  echo "Run 'Install ICMP Tunnel' first." >&2
  exit 1
fi

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Config file not found: ${CONFIG_FILE}" >&2
  echo "Run '${ROLE} setup' first." >&2
  exit 1
fi

# If WARP drop-in exists, copy files to /opt/icmptunnel
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
WARP_DROPIN="${DROPIN_DIR}/10-warp.conf"

if [ -f "${WARP_DROPIN}" ] || id -u icmptunnel >/dev/null 2>&1; then
  if [ -x "${ICMPTUNNEL_DIR}/icmptunnel" ] && [ -f "${CONFIG_FILE}" ]; then
    mkdir -p "/opt/icmptunnel/${ROLE}"
    cp -f "${ICMPTUNNEL_DIR}/icmptunnel" "/opt/icmptunnel/icmptunnel"
    cp -f "${CONFIG_FILE}" "/opt/icmptunnel/${ROLE}/config.json"
    if id -u icmptunnel >/dev/null 2>&1; then
      chown root:icmptunnel "/opt/icmptunnel/icmptunnel" "/opt/icmptunnel/${ROLE}/config.json" 2>/dev/null || true
      chmod 750 "/opt/icmptunnel/icmptunnel" || true
      chmod 640 "/opt/icmptunnel/${ROLE}/config.json" || true
    fi
  fi
  if [ -x "/opt/icmptunnel/icmptunnel" ]; then
    BIN_PATH="/opt/icmptunnel/icmptunnel"
    CONFIG_FILE="/opt/icmptunnel/${ROLE}/config.json"
  fi
fi

echo "Using:"
echo "  ICMP Tunnel dir: ${ICMPTUNNEL_DIR}"
echo "  Role dir:        ${ROLE_DIR}"
echo "  Binary:          ${BIN_PATH}"
echo "  Config:          ${CONFIG_FILE}"
echo "  Service:         ${SERVICE_NAME}"

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

# If WARP setup created the icmptunnel user, ensure service runs as that user
if id -u icmptunnel >/dev/null 2>&1; then
  mkdir -p "${DROPIN_DIR}"
  cat > "${WARP_DROPIN}" <<CONF
[Service]
User=icmptunnel
Group=icmptunnel
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
CONF
fi

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  systemctl restart "${SERVICE_NAME}.service"
else
  systemctl start "${SERVICE_NAME}.service"
fi

systemctl status "${SERVICE_NAME}.service" --no-pager
