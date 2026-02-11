#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
CONFIG_DIR="${WATERWALL_DIR}/configs"
CONFIG_FILE="${CONFIG_DIR}/reverse.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_reverse.sh"

mkdir -p "${WATERWALL_DIR}" "${CONFIG_DIR}" "${WATERWALL_DIR}/logs" "${WATERWALL_DIR}/runtime"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

if [ ! -x "${WATERWALL_DIR}/waterwall" ]; then
  echo "Waterwall binary not found: ${WATERWALL_DIR}/waterwall" >&2
  echo "Run 'Install Waterwall' first." >&2
  exit 1
fi

read -r -p "Reverse server bind address [0.0.0.0]: " BIND_ADDR
BIND_ADDR="${BIND_ADDR:-0.0.0.0}"
read -r -p "Reverse server bind port [7001]: " BIND_PORT
BIND_PORT="${BIND_PORT:-7001}"
if ! validate_port "${BIND_PORT}"; then
  echo "Invalid bind port: ${BIND_PORT}" >&2
  exit 1
fi
read -r -p "Local service host/IP [127.0.0.1]: " LOCAL_HOST
LOCAL_HOST="${LOCAL_HOST:-127.0.0.1}"
read -r -p "Local service port [22]: " LOCAL_PORT
LOCAL_PORT="${LOCAL_PORT:-22}"
if ! validate_port "${LOCAL_PORT}"; then
  echo "Invalid local service port: ${LOCAL_PORT}" >&2
  exit 1
fi

cat > "${CONFIG_FILE}" <<EOF
{
  "mode": "reverse",
  "bind": {
    "address": "${BIND_ADDR}",
    "port": ${BIND_PORT}
  },
  "local_service": {
    "host": "${LOCAL_HOST}",
    "port": ${LOCAL_PORT}
  },
  "notes": "Adjust this template to match your Waterwall release schema if needed."
}
EOF

cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if "${WATERWALL_DIR}/waterwall" --help 2>/dev/null | grep -q -- '-c'; then
  exec "${WATERWALL_DIR}/waterwall" -c "${CONFIG_FILE}"
else
  exec "${WATERWALL_DIR}/waterwall" "${CONFIG_FILE}"
fi
EOF
chmod +x "${RUN_SCRIPT}"

echo "Reverse tunnel config written: ${CONFIG_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
