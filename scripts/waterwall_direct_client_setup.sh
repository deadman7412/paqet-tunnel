#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
CONFIG_DIR="${WATERWALL_DIR}/configs"
CONFIG_FILE="${CONFIG_DIR}/direct_client.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_client.sh"

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

read -r -p "Local listen address [127.0.0.1]: " LOCAL_LISTEN_ADDR
LOCAL_LISTEN_ADDR="${LOCAL_LISTEN_ADDR:-127.0.0.1}"
read -r -p "Local listen port [1080]: " LOCAL_LISTEN_PORT
LOCAL_LISTEN_PORT="${LOCAL_LISTEN_PORT:-1080}"
if ! validate_port "${LOCAL_LISTEN_PORT}"; then
  echo "Invalid local listen port: ${LOCAL_LISTEN_PORT}" >&2
  exit 1
fi

read -r -p "Foreign server address/IP: " FOREIGN_ADDR
if [ -z "${FOREIGN_ADDR}" ]; then
  echo "Foreign server address is required." >&2
  exit 1
fi
read -r -p "Foreign server port [443]: " FOREIGN_PORT
FOREIGN_PORT="${FOREIGN_PORT:-443}"
if ! validate_port "${FOREIGN_PORT}"; then
  echo "Invalid foreign server port: ${FOREIGN_PORT}" >&2
  exit 1
fi

read -r -p "TLS SNI (domain on cert) [www.cloudflare.com]: " TLS_SNI
TLS_SNI="${TLS_SNI:-www.cloudflare.com}"
read -r -p "gRPC service name [GunService]: " GRPC_SERVICE
GRPC_SERVICE="${GRPC_SERVICE:-GunService}"
read -r -p "Obfuscator password [change-me-strong-pass]: " OBF_PASSWORD
OBF_PASSWORD="${OBF_PASSWORD:-change-me-strong-pass}"

cat > "${CONFIG_FILE}" <<EOF
{
  "name": "secure-direct-client",
  "nodes": [
    {
      "name": "in",
      "type": "TcpListener",
      "settings": {
        "address": "${LOCAL_LISTEN_ADDR}",
        "port": ${LOCAL_LISTEN_PORT},
        "nodelay": true
      },
      "next": "obfs"
    },
    {
      "name": "obfs",
      "type": "ObfuscatorClient",
      "settings": {
        "password": "${OBF_PASSWORD}"
      },
      "next": "pb"
    },
    {
      "name": "pb",
      "type": "ProtoBufClient",
      "next": "h2"
    },
    {
      "name": "h2",
      "type": "Http2Client",
      "settings": {
        "host": "www.cloudflare.com",
        "path": "/${GRPC_SERVICE}",
        "mode": "grpc"
      },
      "next": "tls"
    },
    {
      "name": "tls",
      "type": "OpenSSLClient",
      "settings": {
        "sni": "${TLS_SNI}",
        "insecure": false,
        "verify_cert": true,
        "alpn": [
          "h2",
          "http/1.1"
        ],
        "fingerprint": "chrome",
        "certificates": "any"
      },
      "next": "out"
    },
    {
      "name": "out",
      "type": "TcpConnector",
      "settings": {
        "address": "${FOREIGN_ADDR}",
        "port": ${FOREIGN_PORT}
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
echo "Direct client config written: ${CONFIG_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
echo "Use same gRPC service and obfuscator password as the foreign server."
