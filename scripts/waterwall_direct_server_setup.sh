#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
CONFIG_DIR="${WATERWALL_DIR}/configs"
CONFIG_FILE="${CONFIG_DIR}/direct_server.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_server.sh"

mkdir -p "${WATERWALL_DIR}" "${CONFIG_DIR}" "${WATERWALL_DIR}/logs" "${WATERWALL_DIR}/runtime" "${WATERWALL_DIR}/certs"

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

read -r -p "Server listen address [0.0.0.0]: " LISTEN_ADDR
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
read -r -p "Server listen port [443]: " LISTEN_PORT
LISTEN_PORT="${LISTEN_PORT:-443}"
if ! validate_port "${LISTEN_PORT}"; then
  echo "Invalid listen port: ${LISTEN_PORT}" >&2
  exit 1
fi

read -r -p "Backend service host [127.0.0.1]: " BACKEND_HOST
BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
read -r -p "Backend service port [2080]: " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-2080}"
if ! validate_port "${BACKEND_PORT}"; then
  echo "Invalid backend service port: ${BACKEND_PORT}" >&2
  exit 1
fi

read -r -p "gRPC service name [GunService]: " GRPC_SERVICE
GRPC_SERVICE="${GRPC_SERVICE:-GunService}"
read -r -p "Obfuscator password [change-me-strong-pass]: " OBF_PASSWORD
OBF_PASSWORD="${OBF_PASSWORD:-change-me-strong-pass}"

read -r -p "TLS cert file [${WATERWALL_DIR}/certs/fullchain.pem]: " CERT_FILE
CERT_FILE="${CERT_FILE:-${WATERWALL_DIR}/certs/fullchain.pem}"
read -r -p "TLS key file [${WATERWALL_DIR}/certs/privkey.pem]: " KEY_FILE
KEY_FILE="${KEY_FILE:-${WATERWALL_DIR}/certs/privkey.pem}"

if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
  echo "Warning: cert/key file does not exist yet." >&2
  echo "Cert: ${CERT_FILE}" >&2
  echo "Key : ${KEY_FILE}" >&2
fi

cat > "${CONFIG_FILE}" <<EOF
{
  "name": "secure-direct-server",
  "nodes": [
    {
      "name": "in",
      "type": "TcpListener",
      "settings": {
        "address": "${LISTEN_ADDR}",
        "port": ${LISTEN_PORT},
        "nodelay": true
      },
      "next": "tls"
    },
    {
      "name": "tls",
      "type": "OpenSSLServer",
      "settings": {
        "cert_file": "${CERT_FILE}",
        "key_file": "${KEY_FILE}",
        "alpn": [
          "h2",
          "http/1.1"
        ]
      },
      "next": "h2"
    },
    {
      "name": "h2",
      "type": "Http2Server",
      "settings": {
        "host": "www.cloudflare.com",
        "path": "/${GRPC_SERVICE}",
        "mode": "grpc"
      },
      "next": "pb"
    },
    {
      "name": "pb",
      "type": "ProtoBufServer",
      "next": "obfs"
    },
    {
      "name": "obfs",
      "type": "ObfuscatorServer",
      "settings": {
        "password": "${OBF_PASSWORD}"
      },
      "next": "out"
    },
    {
      "name": "out",
      "type": "TcpConnector",
      "settings": {
        "address": "${BACKEND_HOST}",
        "port": ${BACKEND_PORT}
      }
    }
  ]
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

echo
echo "Direct server config written: ${CONFIG_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
echo "Make sure client uses the same gRPC service and obfuscator password."
