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
CONFIG_PATH="${WATERWALL_DIR}/direct_${ROLE}.config.json"
LEGACY_CONFIG_PATH="${WATERWALL_DIR}/configs/direct_${ROLE}.json"
CORE_PATH="${WATERWALL_DIR}/core_${ROLE}.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_${ROLE}.sh"
SERVICE_NAME="waterwall-direct-${ROLE}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

install_runtime_libs() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y libatomic1 libstdc++6 >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y libatomic libstdc++ >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y libatomic libstdc++ >/dev/null 2>&1 || true
  fi
}

ensure_runtime_ready() {
  local missing=""
  if ! command -v ldd >/dev/null 2>&1; then
    return 0
  fi
  missing="$(ldd "${BIN_PATH}" 2>/dev/null | awk '/not found/ {print $1}' || true)"
  if [ -n "${missing}" ]; then
    echo "Missing shared libraries detected:"
    echo "${missing}" | sed 's/^/  - /'
    echo "Installing runtime dependencies..."
    install_runtime_libs
    missing="$(ldd "${BIN_PATH}" 2>/dev/null | awk '/not found/ {print $1}' || true)"
    if [ -n "${missing}" ]; then
      echo "Still missing shared libraries after install attempt:" >&2
      echo "${missing}" | sed 's/^/  - /' >&2
      exit 1
    fi
  fi
}

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
  if [ -f "${LEGACY_CONFIG_PATH}" ]; then
    CONFIG_PATH="${LEGACY_CONFIG_PATH}"
  else
    echo "Config not found: ${CONFIG_PATH}" >&2
    echo "Legacy config not found: ${LEGACY_CONFIG_PATH}" >&2
    echo "Run Direct Waterwall ${ROLE} setup first." >&2
    exit 1
  fi
fi
if [ ! -f "${CORE_PATH}" ]; then
  mkdir -p "${WATERWALL_DIR}/log" "${WATERWALL_DIR}/logs" "${WATERWALL_DIR}/runtime"
  cat > "${CORE_PATH}" <<EOF
{
  "log": {
    "path": "log/",
    "core": {
      "loglevel": "DEBUG",
      "file": "core.log",
      "console": true
    },
    "network": {
      "loglevel": "DEBUG",
      "file": "network.log",
      "console": true
    },
    "dns": {
      "loglevel": "SILENT",
      "file": "dns.log",
      "console": false
    }
  },
  "dns": {},
  "misc": {
    "workers": 0,
    "ram-profile": "${ROLE}",
    "libs-path": "libs/"
  },
  "configs": [
    "${CONFIG_PATH#${WATERWALL_DIR}/}"
  ]
}
EOF
  echo "Generated missing core file: ${CORE_PATH}"
fi

if [ ! -f "${RUN_SCRIPT}" ]; then
  cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${WATERWALL_DIR}"
exec "${BIN_PATH}" "${CORE_PATH}"
EOF
fi
chmod +x "${RUN_SCRIPT}"

ensure_runtime_ready

echo "Using:"
echo "  Waterwall dir: ${WATERWALL_DIR}"
echo "  Binary:        ${BIN_PATH}"
echo "  Config:        ${CONFIG_PATH}"
echo "  Core:          ${CORE_PATH}"
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
