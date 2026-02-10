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

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
BIN_PATH="${WATERWALL_DIR}/waterwall"
CONFIG_PATH="${WATERWALL_DIR}/configs/direct_${ROLE}.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_${ROLE}.sh"
SERVICE_NAME="waterwall-direct-${ROLE}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

if [ ! -x "${BIN_PATH}" ]; then
  if [ -f "${BIN_PATH}" ]; then
    chmod +x "${BIN_PATH}" || true
  fi
fi
if [ ! -x "${BIN_PATH}" ]; then
  echo "Waterwall binary not found or not executable: ${BIN_PATH}" >&2
  echo "Run Waterwall install first." >&2
  exit 1
fi

if [ ! -f "${CONFIG_PATH}" ]; then
  echo "Config not found: ${CONFIG_PATH}" >&2
  echo "Run Direct Waterwall ${ROLE} setup first." >&2
  exit 1
fi

if [ ! -f "${RUN_SCRIPT}" ]; then
  cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if "${BIN_PATH}" --help 2>/dev/null | grep -q -- '-c'; then
  exec "${BIN_PATH}" -c "${CONFIG_PATH}"
else
  exec "${BIN_PATH}" "${CONFIG_PATH}"
fi
EOF
  chmod +x "${RUN_SCRIPT}"
fi

echo "Using:"
echo "  Waterwall dir: ${WATERWALL_DIR}"
echo "  Binary:        ${BIN_PATH}"
echo "  Config:        ${CONFIG_PATH}"
echo "  Run script:    ${RUN_SCRIPT}"
echo "  Service:       ${SERVICE_NAME}"

cat > "${UNIT_PATH}" <<EOF
[Unit]
Description=Waterwall Direct ${ROLE} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${WATERWALL_DIR}
ExecStart=${RUN_SCRIPT}
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"
systemctl status "${SERVICE_NAME}.service" --no-pager
