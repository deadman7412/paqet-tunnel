#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_DIR="${ROLE_DIR}/configs"
CONFIG_FILE="${ROLE_DIR}/config.json"
CORE_FILE="${ROLE_DIR}/core.json"
ROLE_CONFIG_FILE="${ROLE_DIR}/direct_client.config.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_client.sh"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

mkdir -p "${WATERWALL_DIR}" "${ROLE_DIR}" "${CONFIG_DIR}" "${ROLE_DIR}/logs" "${ROLE_DIR}/log" "${ROLE_DIR}/runtime"

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

sync_ufw_tunnel_rule_client() {
  local server_ip="$1" server_port="$2"
  local -a rules=()
  local do_install=""
  local do_enable=""
  local do_open=""

  if ! command -v ufw >/dev/null 2>&1; then
    read -r -p "UFW is not installed. Install it now and allow outbound tunnel to ${server_ip}:${server_port}? [y/N]: " do_install
    case "${do_install}" in
      y|Y|yes|YES)
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -y
          DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
        elif command -v dnf >/dev/null 2>&1; then
          dnf install -y ufw
        elif command -v yum >/dev/null 2>&1; then
          yum install -y ufw
        else
          echo "No supported package manager found for UFW install." >&2
          return 0
        fi
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    read -r -p "UFW is installed but inactive. Enable UFW and allow outbound tunnel now? [y/N]: " do_enable
    case "${do_enable}" in
      y|Y|yes|YES)
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow in on lo comment 'waterwall-loopback' >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  read -r -p "Allow outbound tunnel to ${server_ip}:${server_port} in UFW now? [Y/n]: " do_open
  case "${do_open:-Y}" in
    n|N|no|NO)
      echo "Skipped opening outbound tunnel rule in UFW."
      return 0
      ;;
  esac

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/waterwall-tunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi

  ufw allow out to "${server_ip}" port "${server_port}" proto tcp comment 'waterwall-tunnel' >/dev/null 2>&1 || true
  echo "UFW: allowed outbound waterwall tunnel to ${server_ip}:${server_port}."
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
SERVICE_PORT_DEFAULT="1080"
TLS_ENABLED_DEFAULT="1"
TUNNEL_PROFILE_DEFAULT="basic"
TLS_SNI_DEFAULT=""
GRPC_DEFAULT="svc-$(rand_hex 4)"
OBF_DEFAULT="$(rand_hex 16)"

if [ -f "${INFO_PATH}" ]; then
  SERVER_IP_DEFAULT="$(read_info "${INFO_PATH}" "server_public_ip")"
  SERVER_PORT_DEFAULT="$(read_info "${INFO_PATH}" "listen_port")"
  SERVICE_PORT_DEFAULT="$(read_info "${INFO_PATH}" "backend_port")"
  TLS_ENABLED_DEFAULT="$(read_info "${INFO_PATH}" "use_tls")"
  TUNNEL_PROFILE_DEFAULT="$(read_info "${INFO_PATH}" "tunnel_profile")"
  TLS_SNI_DEFAULT="$(read_info "${INFO_PATH}" "tls_sni")"
  GRPC_DEFAULT="$(read_info "${INFO_PATH}" "grpc_service")"
  OBF_DEFAULT="$(read_info "${INFO_PATH}" "obfuscator_password")"
  [ "${SERVER_IP_DEFAULT}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ] && SERVER_IP_DEFAULT=""
  [ -z "${SERVER_PORT_DEFAULT}" ] && SERVER_PORT_DEFAULT="443"
  [ -z "${SERVICE_PORT_DEFAULT}" ] && SERVICE_PORT_DEFAULT="1080"
  [ -z "${TLS_ENABLED_DEFAULT}" ] && TLS_ENABLED_DEFAULT="1"
  [ -z "${TUNNEL_PROFILE_DEFAULT}" ] && TUNNEL_PROFILE_DEFAULT="basic"
  [ -z "${GRPC_DEFAULT}" ] && GRPC_DEFAULT="svc-$(rand_hex 4)"
  [ -z "${OBF_DEFAULT}" ] && OBF_DEFAULT="$(rand_hex 16)"
fi

read -r -p "Local listen address [127.0.0.1]: " LOCAL_LISTEN_ADDR
LOCAL_LISTEN_ADDR="${LOCAL_LISTEN_ADDR:-127.0.0.1}"

read -r -p "Foreign server address/IP [${SERVER_IP_DEFAULT}]: " FOREIGN_ADDR
FOREIGN_ADDR="${FOREIGN_ADDR:-${SERVER_IP_DEFAULT}}"
if [ -z "${FOREIGN_ADDR}" ]; then
  echo "Foreign server address is required." >&2
  exit 1
fi

read -r -p "Service port (must match server backend service port) [${SERVICE_PORT_DEFAULT}]: " LOCAL_LISTEN_PORT
LOCAL_LISTEN_PORT="${LOCAL_LISTEN_PORT:-${SERVICE_PORT_DEFAULT}}"
if ! validate_port "${LOCAL_LISTEN_PORT}"; then
  echo "Invalid service/local listen port: ${LOCAL_LISTEN_PORT}" >&2
  exit 1
fi

read -r -p "Tunnel port (must match server listen port) [${SERVER_PORT_DEFAULT}]: " TUNNEL_PORT
TUNNEL_PORT="${TUNNEL_PORT:-${SERVER_PORT_DEFAULT}}"
if ! validate_port "${TUNNEL_PORT}"; then
  echo "Invalid tunnel/server port: ${TUNNEL_PORT}" >&2
  exit 1
fi
FOREIGN_PORT="${TUNNEL_PORT}"

read -r -p "Tunnel profile [basic/advanced] (default ${TUNNEL_PROFILE_DEFAULT}): " TUNNEL_PROFILE
TUNNEL_PROFILE="$(echo "${TUNNEL_PROFILE:-${TUNNEL_PROFILE_DEFAULT}}" | tr '[:upper:]' '[:lower:]')"
case "${TUNNEL_PROFILE}" in
  basic|advanced) ;;
  *)
    echo "Tunnel profile must be basic or advanced." >&2
    exit 1
    ;;
esac

TLS_ENABLED="0"
TLS_SNI=""
GRPC_SERVICE=""
OBF_PASSWORD=""
if [ "${TUNNEL_PROFILE}" = "advanced" ]; then
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
  fi

  read -r -p "gRPC service name [${GRPC_DEFAULT}]: " GRPC_SERVICE
  GRPC_SERVICE="${GRPC_SERVICE:-${GRPC_DEFAULT}}"
  read -r -p "Obfuscator password [auto]: " OBF_PASSWORD
  OBF_PASSWORD="${OBF_PASSWORD:-${OBF_DEFAULT}}"
fi

if [ "${TUNNEL_PROFILE}" = "basic" ]; then
  cat > "${ROLE_CONFIG_FILE}" <<EOF
{
  "name": "direct-client-basic",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LOCAL_LISTEN_ADDR}",
        "port": ${LOCAL_LISTEN_PORT},
        "nodelay": true
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
elif [ "${TLS_ENABLED}" = "1" ]; then
  cat > "${ROLE_CONFIG_FILE}" <<EOF
{
  "name": "secure-direct-client",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
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
  echo "Advanced mode without TLS is not supported on this host build; using basic chain." >&2
  TUNNEL_PROFILE="basic"
  cat > "${ROLE_CONFIG_FILE}" <<EOF
{
  "name": "direct-client-basic",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LOCAL_LISTEN_ADDR}",
        "port": ${LOCAL_LISTEN_PORT},
        "nodelay": true
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
fi

cp -f "${ROLE_CONFIG_FILE}" "${CONFIG_FILE}"

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
    "config.json"
  ]
}
EOF

cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${ROLE_DIR}"
exec "${WATERWALL_DIR}/waterwall"
EOF
chmod +x "${RUN_SCRIPT}"

echo
echo "Direct client config written: ${ROLE_CONFIG_FILE}"
echo "Active config written: ${CONFIG_FILE}"
echo "Core file written: ${CORE_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
echo "Role dir: ${ROLE_DIR}"
echo "Using values:"
echo "  - tunnel_profile: ${TUNNEL_PROFILE}"
echo "  - tunnel_port: ${TUNNEL_PORT}"
echo "  - service_port(local/client): ${LOCAL_LISTEN_PORT}"
echo "  - service_port(server/backend): ${LOCAL_LISTEN_PORT}"
echo "  - foreign_addr: ${FOREIGN_ADDR}"
echo "  - foreign_port: ${FOREIGN_PORT}"
echo "  - use_tls: ${TLS_ENABLED}"
if [ -n "${GRPC_SERVICE}" ]; then
  echo "  - grpc_service: ${GRPC_SERVICE}"
fi
if [ -n "${OBF_PASSWORD}" ]; then
  echo "  - obfuscator_password: ${OBF_PASSWORD}"
fi

sync_ufw_tunnel_rule_client "${FOREIGN_ADDR}" "${FOREIGN_PORT}"
