#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
CONFIG_DIR="${WATERWALL_DIR}/configs"
CONFIG_FILE="${WATERWALL_DIR}/direct_client.config.json"
CORE_FILE="${WATERWALL_DIR}/core_client.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_client.sh"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

mkdir -p "${WATERWALL_DIR}" "${CONFIG_DIR}" "${WATERWALL_DIR}/logs" "${WATERWALL_DIR}/log" "${WATERWALL_DIR}/runtime"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

random_port() {
  local p
  p="$(shuf -i 20000-60000 -n 1 2>/dev/null || true)"
  if [ -z "${p}" ]; then
    p="$(( (RANDOM % 40001) + 20000 ))"
  fi
  echo "${p}"
}

rand_hex() {
  local n="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "${n}" 2>/dev/null || true
  else
    head -c "${n}" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

read_info() {
  local file="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub($1"=",""); print; exit}' "${file}" 2>/dev/null || true
}

if [ ! -x "${WATERWALL_DIR}/waterwall" ]; then
  echo "Waterwall binary not found: ${WATERWALL_DIR}/waterwall" >&2
  echo "Run 'Install Waterwall' first." >&2
  exit 1
fi

INFO_PATH_DEFAULT="${INFO_FILE}"
read -r -p "Server info file path [${INFO_PATH_DEFAULT}] (leave empty to skip): " INFO_PATH
INFO_PATH="${INFO_PATH:-${INFO_PATH_DEFAULT}}"

SERVER_IP_DEFAULT=""
SERVER_PORT_DEFAULT="443"
TLS_ENABLED_DEFAULT="1"
TLS_SNI_DEFAULT=""
GRPC_DEFAULT="svc-$(rand_hex 4)"
OBF_DEFAULT="$(rand_hex 16)"

if [ -f "${INFO_PATH}" ]; then
  SERVER_IP_DEFAULT="$(read_info "${INFO_PATH}" "server_public_ip")"
  SERVER_PORT_DEFAULT="$(read_info "${INFO_PATH}" "listen_port")"
  TLS_ENABLED_DEFAULT="$(read_info "${INFO_PATH}" "use_tls")"
  TLS_SNI_DEFAULT="$(read_info "${INFO_PATH}" "tls_sni")"
  GRPC_DEFAULT="$(read_info "${INFO_PATH}" "grpc_service")"
  OBF_DEFAULT="$(read_info "${INFO_PATH}" "obfuscator_password")"
  [ "${SERVER_IP_DEFAULT}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ] && SERVER_IP_DEFAULT=""
  [ -z "${SERVER_PORT_DEFAULT}" ] && SERVER_PORT_DEFAULT="443"
  [ -z "${TLS_ENABLED_DEFAULT}" ] && TLS_ENABLED_DEFAULT="1"
  [ -z "${GRPC_DEFAULT}" ] && GRPC_DEFAULT="svc-$(rand_hex 4)"
  [ -z "${OBF_DEFAULT}" ] && OBF_DEFAULT="$(rand_hex 16)"
fi

read -r -p "Local listen address [127.0.0.1]: " LOCAL_LISTEN_ADDR
LOCAL_LISTEN_ADDR="${LOCAL_LISTEN_ADDR:-127.0.0.1}"
LOCAL_PORT_DEFAULT="$(random_port)"
read -r -p "Local listen port [${LOCAL_PORT_DEFAULT}]: " LOCAL_LISTEN_PORT
LOCAL_LISTEN_PORT="${LOCAL_LISTEN_PORT:-${LOCAL_PORT_DEFAULT}}"
if ! validate_port "${LOCAL_LISTEN_PORT}"; then
  echo "Invalid local listen port: ${LOCAL_LISTEN_PORT}" >&2
  exit 1
fi

read -r -p "Foreign server address/IP [${SERVER_IP_DEFAULT}]: " FOREIGN_ADDR
FOREIGN_ADDR="${FOREIGN_ADDR:-${SERVER_IP_DEFAULT}}"
if [ -z "${FOREIGN_ADDR}" ]; then
  echo "Foreign server address is required." >&2
  exit 1
fi
read -r -p "Foreign server port [${SERVER_PORT_DEFAULT}]: " FOREIGN_PORT
FOREIGN_PORT="${FOREIGN_PORT:-${SERVER_PORT_DEFAULT}}"
if ! validate_port "${FOREIGN_PORT}"; then
  echo "Invalid foreign server port: ${FOREIGN_PORT}" >&2
  exit 1
fi

read -r -p "Use TLS for this tunnel? [${TLS_ENABLED_DEFAULT}] (1/0): " TLS_ENABLED
TLS_ENABLED="${TLS_ENABLED:-${TLS_ENABLED_DEFAULT}}"
if [ "${TLS_ENABLED}" != "1" ] && [ "${TLS_ENABLED}" != "0" ]; then
  echo "TLS value must be 1 or 0." >&2
  exit 1
fi

if [ "${TLS_ENABLED}" = "1" ]; then
  TLS_SNI_DEFAULT="${TLS_SNI_DEFAULT:-www.cloudflare.com}"
  read -r -p "TLS SNI (domain on cert) [${TLS_SNI_DEFAULT}]: " TLS_SNI
  TLS_SNI="${TLS_SNI:-${TLS_SNI_DEFAULT}}"
else
  TLS_SNI=""
fi

read -r -p "gRPC service name [${GRPC_DEFAULT}]: " GRPC_SERVICE
GRPC_SERVICE="${GRPC_SERVICE:-${GRPC_DEFAULT}}"
read -r -p "Obfuscator password [auto]: " OBF_PASSWORD
OBF_PASSWORD="${OBF_PASSWORD:-${OBF_DEFAULT}}"

if [ "${TLS_ENABLED}" = "1" ]; then
  cat > "${CONFIG_FILE}" <<EOF
{
  "name": "secure-direct-client",
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LOCAL_LISTEN_ADDR}",
        "port": ${LOCAL_LISTEN_PORT},
        "nodelay": true
      },
      "next": "obfuscator_client"
    },
    {
      "name": "obfuscator_client",
      "type": "ObfuscatorClient",
      "settings": {
        "password": "${OBF_PASSWORD}"
      },
      "next": "protobuf_client"
    },
    {
      "name": "protobuf_client",
      "type": "ProtoBufClient",
      "next": "h2_client"
    },
    {
      "name": "h2_client",
      "type": "Http2Client",
      "settings": {
        "host": "${TLS_SNI}",
        "path": "/${GRPC_SERVICE}",
        "mode": "grpc"
      },
      "next": "tls_client"
    },
    {
      "name": "tls_client",
      "type": "OpenSSLClient",
      "settings": {
        "sni": "${TLS_SNI}",
        "verify": true,
        "alpns": [
          "h2",
          "http/1.1"
        ],
        "fingerprint": "chrome"
      },
      "next": "output"
    },
    {
      "name": "output",
      "type": "TcpConnector",
      "settings": {
        "address": "${FOREIGN_ADDR}",
        "port": ${FOREIGN_PORT},
        "nodelay": true
      }
    }
  ]
}
EOF
else
  cat > "${CONFIG_FILE}" <<EOF
{
  "name": "direct-client-no-tls",
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LOCAL_LISTEN_ADDR}",
        "port": ${LOCAL_LISTEN_PORT},
        "nodelay": true
      },
      "next": "obfuscator_client"
    },
    {
      "name": "obfuscator_client",
      "type": "ObfuscatorClient",
      "settings": {
        "password": "${OBF_PASSWORD}"
      },
      "next": "protobuf_client"
    },
    {
      "name": "protobuf_client",
      "type": "ProtoBufClient",
      "next": "output"
    },
    {
      "name": "output",
      "type": "TcpConnector",
      "settings": {
        "address": "${FOREIGN_ADDR}",
        "port": ${FOREIGN_PORT},
        "nodelay": true
      }
    }
  ]
}
EOF
fi

cat > "${CORE_FILE}" <<EOF
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
    "ram-profile": "client",
    "libs-path": "libs/"
  },
  "configs": [
    "$(basename "${CONFIG_FILE}")"
  ]
}
EOF

cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${WATERWALL_DIR}"
exec "${WATERWALL_DIR}/waterwall" "${CORE_FILE}"
EOF
chmod +x "${RUN_SCRIPT}"

echo
echo "Direct client config written: ${CONFIG_FILE}"
echo "Core file written: ${CORE_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
echo "Using values:"
echo "  - foreign_addr: ${FOREIGN_ADDR}"
echo "  - foreign_port: ${FOREIGN_PORT}"
echo "  - use_tls: ${TLS_ENABLED}"
echo "  - grpc_service: ${GRPC_SERVICE}"
echo "  - obfuscator_password: ${OBF_PASSWORD}"
