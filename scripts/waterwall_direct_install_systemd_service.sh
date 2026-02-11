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
ROLE_DIR="${WATERWALL_DIR}/${ROLE}"
BIN_PATH="${WATERWALL_DIR}/waterwall"
ACTIVE_CONFIG="${ROLE_DIR}/config.json"
ACTIVE_CORE="${ROLE_DIR}/core.json"
ROLE_CONFIG="${ROLE_DIR}/direct_${ROLE}.config.json"
LEGACY_ROLE_CONFIG="${WATERWALL_DIR}/configs/direct_${ROLE}.json"
LEGACY_ROOT_ROLE_CONFIG="${WATERWALL_DIR}/direct_${ROLE}.config.json"
LEGACY_ROLE_CORE="${WATERWALL_DIR}/core_${ROLE}.json"
LEGACY_ROOT_CONFIG="${WATERWALL_DIR}/config.json"
LEGACY_ROOT_CORE="${WATERWALL_DIR}/core.json"
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

ensure_active_files() {
  mkdir -p "${ROLE_DIR}/log" "${ROLE_DIR}/logs" "${ROLE_DIR}/runtime"

  if [ ! -f "${ACTIVE_CONFIG}" ]; then
    if [ -f "${ROLE_CONFIG}" ]; then
      cp -f "${ROLE_CONFIG}" "${ACTIVE_CONFIG}"
    elif [ -f "${LEGACY_ROOT_ROLE_CONFIG}" ]; then
      cp -f "${LEGACY_ROOT_ROLE_CONFIG}" "${ACTIVE_CONFIG}"
    elif [ -f "${LEGACY_ROLE_CONFIG}" ]; then
      cp -f "${LEGACY_ROLE_CONFIG}" "${ACTIVE_CONFIG}"
    elif [ -f "${LEGACY_ROOT_CONFIG}" ]; then
      cp -f "${LEGACY_ROOT_CONFIG}" "${ACTIVE_CONFIG}"
    else
      echo "Active config not found: ${ACTIVE_CONFIG}" >&2
      echo "Role config not found: ${ROLE_CONFIG}" >&2
      echo "Legacy root role config not found: ${LEGACY_ROOT_ROLE_CONFIG}" >&2
      echo "Legacy role config not found: ${LEGACY_ROLE_CONFIG}" >&2
      echo "Legacy root config not found: ${LEGACY_ROOT_CONFIG}" >&2
      echo "Run Direct Waterwall ${ROLE} setup first." >&2
      exit 1
    fi
  fi

  if [ ! -f "${ACTIVE_CORE}" ]; then
    if [ -f "${LEGACY_ROLE_CORE}" ]; then
      cp -f "${LEGACY_ROLE_CORE}" "${ACTIVE_CORE}"
    elif [ -f "${LEGACY_ROOT_CORE}" ]; then
      cp -f "${LEGACY_ROOT_CORE}" "${ACTIVE_CORE}"
    else
      cat > "${ACTIVE_CORE}" <<EOF
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
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ]
  },
  "misc": {
    "workers": 0,
    "ram-profile": "${ROLE}",
    "libs-path": "libs/"
  },
  "configs": [
    "config.json"
  ]
}
EOF
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

ensure_active_files
ensure_runtime_ready

# Always refresh run script to avoid stale legacy commands.
cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${ROLE_DIR}"
exec "${BIN_PATH}"
EOF
chmod +x "${RUN_SCRIPT}"

echo "Using:"
echo "  Waterwall dir: ${WATERWALL_DIR}"
echo "  Role dir:      ${ROLE_DIR}"
echo "  Binary:        ${BIN_PATH}"
echo "  Config:        ${ACTIVE_CONFIG}"
echo "  Core:          ${ACTIVE_CORE}"
echo "  Run script:    ${RUN_SCRIPT}"
echo "  Service:       ${SERVICE_NAME}"

cat > "${UNIT_PATH}" <<EOF
[Unit]
Description=Waterwall Direct ${ROLE} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROLE_DIR}
ExecStart=${RUN_SCRIPT}
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  systemctl restart "${SERVICE_NAME}.service"
else
  systemctl start "${SERVICE_NAME}.service"
fi
systemctl status "${SERVICE_NAME}.service" --no-pager
