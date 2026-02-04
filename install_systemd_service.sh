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

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
BIN_PATH="${BIN_PATH:-${PAQET_DIR}/paqet}"
CONFIG_PATH="${CONFIG_PATH:-${PAQET_DIR}/${ROLE}.yaml}"
SERVICE_NAME="${SERVICE_NAME:-paqet-${ROLE}}"

if [ ! -x "${BIN_PATH}" ]; then
  if [ -f "${BIN_PATH}" ]; then
    chmod +x "${BIN_PATH}" || true
  fi
fi

WARP_DROPIN="/etc/systemd/system/${SERVICE_NAME}.service.d/10-warp.conf"
if [ -f "${WARP_DROPIN}" ] || id -u paqet >/dev/null 2>&1; then
  # Ensure /opt/paqet exists and is accessible to paqet user
  if [ -x "/root/paqet/paqet" ] && [ -f "/root/paqet/${ROLE}.yaml" ]; then
    mkdir -p /opt/paqet
    cp -f "/root/paqet/paqet" "/opt/paqet/paqet"
    cp -f "/root/paqet/${ROLE}.yaml" "/opt/paqet/${ROLE}.yaml"
    chown root:paqet "/opt/paqet/paqet" "/opt/paqet/${ROLE}.yaml" 2>/dev/null || true
    chmod 750 "/opt/paqet/paqet" || true
    chmod 640 "/opt/paqet/${ROLE}.yaml" || true
  fi
  if [ -x "/opt/paqet/paqet" ]; then
    BIN_PATH="/opt/paqet/paqet"
    CONFIG_PATH="/opt/paqet/${ROLE}.yaml"
  fi
fi

if [ ! -x "${BIN_PATH}" ]; then
  echo "Binary not found or not executable: ${BIN_PATH}" >&2
  exit 1
fi

if [ ! -f "${CONFIG_PATH}" ]; then
  echo "Config file not found: ${CONFIG_PATH}" >&2
  exit 1
fi

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Using:"
echo "  Paqet dir: ${PAQET_DIR}"
echo "  Binary:   ${BIN_PATH}"
echo "  Config:   ${CONFIG_PATH}"
echo "  Service:  ${SERVICE_NAME}"

cat <<UNIT > "${UNIT_PATH}"
[Unit]
Description=Paqet ${ROLE} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} run -c ${CONFIG_PATH}
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

systemctl status "${SERVICE_NAME}.service" --no-pager
