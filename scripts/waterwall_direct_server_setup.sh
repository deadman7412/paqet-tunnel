#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/server"
CONFIG_DIR="${ROLE_DIR}/configs"
CONFIG_FILE="${ROLE_DIR}/config.json"
CORE_FILE="${ROLE_DIR}/core.json"
ROLE_CONFIG_FILE="${ROLE_DIR}/direct_server.config.json"
RUN_SCRIPT="${WATERWALL_DIR}/run_direct_server.sh"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"
INFO_FORMAT_VERSION="1"
CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${WATERWALL_DIR}" "${ROLE_DIR}" "${CONFIG_DIR}" "${ROLE_DIR}/logs" "${ROLE_DIR}/log" "${ROLE_DIR}/runtime" "${WATERWALL_DIR}/certs"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -E "[:.]${p}$" >/dev/null 2>&1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -E "[:.]${p}$" >/dev/null 2>&1
  else
    return 1
  fi
}

random_port() {
  local p tries=0
  while :; do
    p="$(shuf -i 20000-60000 -n 1 2>/dev/null || true)"
    if [ -z "${p}" ]; then
      p="$(( (RANDOM % 40001) + 20000 ))"
    fi
    if ! port_in_use "${p}"; then
      echo "${p}"
      return 0
    fi
    tries=$((tries + 1))
    [ "${tries}" -lt 40 ] || break
  done
  echo "443"
}

rand_hex() {
  local n="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "${n}" 2>/dev/null || true
  else
    head -c "${n}" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

detect_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    ip="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null || true)"
    [ -z "${ip}" ] && ip="$(wget -qO- --timeout=5 https://ipinfo.io/ip 2>/dev/null || true)"
  fi
  echo "${ip}"
}

sync_ufw_tunnel_rule_server() {
  local listen_port="$1"
  local -a rules=()
  local ssh_ports=""
  local do_install=""
  local do_enable=""
  local do_open=""

  if ! command -v ufw >/dev/null 2>&1; then
    read -r -p "UFW is not installed. Install it now and open tunnel port ${listen_port}/tcp? [y/N]: " do_install
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
    read -r -p "UFW is installed but inactive. Enable UFW and open tunnel port ${listen_port}/tcp now? [y/N]: " do_enable
    case "${do_enable}" in
      y|Y|yes|YES)
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow in on lo comment 'waterwall-loopback' >/dev/null 2>&1 || true
        ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
        [ -z "${ssh_ports}" ] && ssh_ports="22"
        for p in ${ssh_ports}; do
          ufw allow "${p}/tcp" comment 'ssh' >/dev/null 2>&1 || true
        done
        ufw --force enable >/dev/null 2>&1 || true
        ;;
      *)
        echo "Skipped firewall changes."
        return 0
        ;;
    esac
  fi

  read -r -p "Open server tunnel port ${listen_port}/tcp in UFW now? [Y/n]: " do_open
  case "${do_open:-Y}" in
    n|N|no|NO)
      echo "Skipped opening tunnel port in UFW."
      return 0
      ;;
  esac

  echo
  echo "IMPORTANT: For security, tunnel port should only accept connections from client IP."
  read -r -p "Enter client public IPv4 address (required): " client_ip
  if [ -z "${client_ip}" ]; then
    echo "[WARN] No client IP provided. Tunnel port will be open to ALL IPs (not recommended)."
    read -r -p "Continue anyway? [y/N]: " continue_open
    case "${continue_open}" in
      y|Y|yes|YES) ;;
      *)
        echo "Skipped opening tunnel port in UFW."
        return 0
        ;;
    esac
  fi

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/waterwall-tunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi

  if [ -n "${client_ip}" ]; then
    ufw allow from "${client_ip}" to any port "${listen_port}" proto tcp comment 'waterwall-tunnel' >/dev/null 2>&1 || true
    echo "UFW: allowed inbound waterwall tunnel on tcp/${listen_port} from ${client_ip} only."
  else
    ufw allow "${listen_port}/tcp" comment 'waterwall-tunnel' >/dev/null 2>&1 || true
    echo "UFW: allowed inbound waterwall tunnel on tcp/${listen_port} from ANY IP."
  fi
}

ensure_certbot() {
  if command -v certbot >/dev/null 2>&1; then
    return 0
  fi
  echo "certbot not found. Installing..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y certbot
  elif command -v yum >/dev/null 2>&1; then
    yum install -y certbot
  else
    echo "No supported package manager found for certbot installation." >&2
    return 1
  fi
}

list_existing_certs() {
  local idx=0 d cert key domain base
  CERT_DOMAINS=()
  CERT_FILES=()
  KEY_FILES=()
  CERT_SOURCES=()
  CERT_KEYS=()

  # Let's Encrypt default layout
  if [ -d /etc/letsencrypt/live ]; then
    for d in /etc/letsencrypt/live/*; do
      [ -d "${d}" ] || continue
      cert="${d}/fullchain.pem"
      key="${d}/privkey.pem"
      [ -f "${cert}" ] || continue
      [ -f "${key}" ] || continue
      domain="$(basename "${d}")"
      entry_key="${domain}|${cert}|${key}"
      if printf "%s\n" "${CERT_KEYS[@]-}" | grep -Fqx "${entry_key}"; then
        continue
      fi
      CERT_DOMAINS+=("${domain}")
      CERT_FILES+=("${cert}")
      KEY_FILES+=("${key}")
      CERT_SOURCES+=("letsencrypt")
      CERT_KEYS+=("${entry_key}")
      idx=$((idx + 1))
    done
  fi

  # acme.sh common locations
  ACME_BASES=("${HOME}/.acme.sh" /root/.acme.sh)
  uniq_bases=()
  for base in "${ACME_BASES[@]}"; do
    [ -n "${base}" ] || continue
    if printf "%s\n" "${uniq_bases[@]-}" | grep -Fqx "${base}"; then
      continue
    fi
    uniq_bases+=("${base}")
  done
  for base in "${uniq_bases[@]}"; do
    [ -d "${base}" ] || continue
    for d in "${base}"/*; do
      [ -d "${d}" ] || continue
      cert=""
      key=""
      if [ -f "${d}/fullchain.cer" ]; then
        cert="${d}/fullchain.cer"
      elif [ -f "${d}/fullchain.pem" ]; then
        cert="${d}/fullchain.pem"
      fi
      key="$(find "${d}" -maxdepth 1 -type f -name "*.key" | head -n1 || true)"
      [ -n "${cert}" ] || continue
      [ -n "${key}" ] || continue
      domain="$(basename "${d}")"
      entry_key="${domain}|${cert}|${key}"
      if printf "%s\n" "${CERT_KEYS[@]-}" | grep -Fqx "${entry_key}"; then
        continue
      fi
      CERT_DOMAINS+=("${domain}")
      CERT_FILES+=("${cert}")
      KEY_FILES+=("${key}")
      CERT_SOURCES+=("acme.sh")
      CERT_KEYS+=("${entry_key}")
      idx=$((idx + 1))
    done
  done

  return 0
}

if [ ! -x "${WATERWALL_DIR}/waterwall" ]; then
  echo "Waterwall binary not found: ${WATERWALL_DIR}/waterwall" >&2
  echo "Run 'Install Waterwall' first." >&2
  exit 1
fi

read -r -p "Server listen address [0.0.0.0]: " LISTEN_ADDR
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
PORT_DEFAULT="$(random_port)"
read -r -p "Server listen port [${PORT_DEFAULT}]: " LISTEN_PORT
LISTEN_PORT="${LISTEN_PORT:-${PORT_DEFAULT}}"
if ! validate_port "${LISTEN_PORT}"; then
  echo "Invalid listen port: ${LISTEN_PORT}" >&2
  exit 1
fi

echo "Tunnel mode: forward (stable mode; backend service required, e.g., 3x-ui/xray inbound)"
read -r -p "Backend service host [127.0.0.1]: " BACKEND_HOST
BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT_DEFAULT="$(random_port)"
read -r -p "Backend service port [${BACKEND_PORT_DEFAULT}]: " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-${BACKEND_PORT_DEFAULT}}"
if ! validate_port "${BACKEND_PORT}"; then
  echo "Invalid backend service port: ${BACKEND_PORT}" >&2
  exit 1
fi

read -r -p "Tunnel profile [basic/advanced] (default basic): " TUNNEL_PROFILE
TUNNEL_PROFILE="$(echo "${TUNNEL_PROFILE:-basic}" | tr '[:upper:]' '[:lower:]')"
case "${TUNNEL_PROFILE}" in
  basic|advanced) ;;
  *)
    echo "Tunnel profile must be basic or advanced." >&2
    exit 1
    ;;
esac

GRPC_SERVICE=""
OBF_PASSWORD=""
TLS_ENABLED="0"
if [ "${TUNNEL_PROFILE}" = "advanced" ]; then
  GRPC_DEFAULT="svc-$(rand_hex 4)"
  read -r -p "gRPC service name [${GRPC_DEFAULT}]: " GRPC_SERVICE
  GRPC_SERVICE="${GRPC_SERVICE:-${GRPC_DEFAULT}}"

  OBF_DEFAULT="$(rand_hex 16)"
  read -r -p "Obfuscator password [auto]: " OBF_PASSWORD
  OBF_PASSWORD="${OBF_PASSWORD:-${OBF_DEFAULT}}"

  read -r -p "Enable TLS for direct tunnel? [Y/n]: " TLS_CHOICE
  case "${TLS_CHOICE:-Y}" in
    n|N|no|NO) TLS_ENABLED="0" ;;
    *) TLS_ENABLED="1" ;;
  esac
fi

CERT_FILE=""
KEY_FILE=""
TLS_SNI=""
if [ "${TUNNEL_PROFILE}" = "advanced" ] && [ "${TLS_ENABLED}" = "1" ]; then
  list_existing_certs
  cert_count="${#CERT_DOMAINS[@]}"
  echo
  echo "Available TLS certificates on this server:"
  if [ "${cert_count}" -gt 0 ]; then
    i=1
    while [ "${i}" -le "${cert_count}" ]; do
      j=$((i - 1))
      echo "  ${i}) ${CERT_DOMAINS[$j]} [${CERT_SOURCES[$j]}]"
      echo "     cert: ${CERT_FILES[$j]}"
      echo "     key : ${KEY_FILES[$j]}"
      i=$((i + 1))
    done
  else
    echo "  (none found)"
  fi
  echo
  echo "TLS setup options:"
  echo "  1) Use an existing certificate from the list"
  echo "  2) Register a new domain certificate with certbot"
  echo "  3) Enter custom cert/key file paths manually"
  read -r -p "Select TLS option [1-3]: " TLS_OPTION
  TLS_OPTION="${TLS_OPTION:-1}"

  case "${TLS_OPTION}" in
    1)
      if [ "${cert_count}" -eq 0 ]; then
        echo "No existing certificates found. Choose option 2 or 3." >&2
        exit 1
      fi
      read -r -p "Select certificate number [1-${cert_count}]: " CERT_IDX
      if ! validate_port "${CERT_IDX}" || [ "${CERT_IDX}" -lt 1 ] || [ "${CERT_IDX}" -gt "${cert_count}" ]; then
        echo "Invalid certificate selection: ${CERT_IDX}" >&2
        exit 1
      fi
      j=$((CERT_IDX - 1))
      CERT_FILE="${CERT_FILES[$j]}"
      KEY_FILE="${KEY_FILES[$j]}"
      TLS_SNI="${CERT_DOMAINS[$j]}"
      ;;
    2)
      read -r -p "Domain for automatic certificate (e.g., tunnel.example.com): " TLS_SNI
      read -r -p "Email for certbot registration: " CERTBOT_EMAIL
      if [ -z "${TLS_SNI}" ] || [ -z "${CERTBOT_EMAIL}" ]; then
        echo "Domain and email are required for automatic TLS provisioning." >&2
        exit 1
      fi
      ensure_certbot || exit 1
      echo "Requesting certificate via certbot standalone..."
      echo "Note: port 80 must be reachable for HTTP challenge."
      certbot certonly --standalone --non-interactive --agree-tos --keep-until-expiring -m "${CERTBOT_EMAIL}" -d "${TLS_SNI}"
      CERT_FILE="/etc/letsencrypt/live/${TLS_SNI}/fullchain.pem"
      KEY_FILE="/etc/letsencrypt/live/${TLS_SNI}/privkey.pem"
      ;;
    3)
      read -r -p "TLS cert file path: " CERT_FILE
      read -r -p "TLS key file path: " KEY_FILE
      read -r -p "TLS SNI/domain (for client): " TLS_SNI
      if [ -z "${CERT_FILE}" ] || [ -z "${KEY_FILE}" ] || [ -z "${TLS_SNI}" ]; then
        echo "cert file, key file, and SNI/domain are required." >&2
        exit 1
      fi
      ;;
    *)
      echo "Invalid TLS option: ${TLS_OPTION}" >&2
      exit 1
      ;;
  esac

  if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
    echo "TLS files not found after selection/provisioning." >&2
    echo "Cert: ${CERT_FILE}" >&2
    echo "Key : ${KEY_FILE}" >&2
    exit 1
  fi
fi

if [ "${TUNNEL_PROFILE}" = "basic" ]; then
  cat > "${ROLE_CONFIG_FILE}" <<EOF
{
  "name": "direct-server-basic",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LISTEN_ADDR}",
        "port": ${LISTEN_PORT},
        "nodelay": true
      },
      "next": "output"
    },
    {
      "name": "output",
      "type": "TcpConnector",
      "settings": {
        "address": "${BACKEND_HOST}",
        "port": ${BACKEND_PORT},
        "nodelay": true
      }
    }
  ]
}
EOF
elif [ "${TLS_ENABLED}" = "1" ]; then
  cat > "${ROLE_CONFIG_FILE}" <<EOF
{
  "name": "secure-direct-server",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LISTEN_ADDR}",
        "port": ${LISTEN_PORT},
        "nodelay": true
      },
      "next": "tls_server"
    },
    {
      "name": "tls_server",
      "type": "OpenSSLServer",
      "settings": {
        "cert-file": "${CERT_FILE}",
        "key-file": "${KEY_FILE}",
        "alpns": [
          "h2",
          "http/1.1"
        ]
      },
      "next": "h2_server"
    },
    {
      "name": "h2_server",
      "type": "Http2Server",
      "settings": {
        "host": "${TLS_SNI}",
        "path": "/${GRPC_SERVICE}",
        "mode": "grpc"
      },
      "next": "protobuf_server"
    },
    {
      "name": "protobuf_server",
      "type": "ProtoBufServer",
      "next": "obfuscator_server"
    },
    {
      "name": "obfuscator_server",
      "type": "ObfuscatorServer",
      "settings": {
        "password": "${OBF_PASSWORD}"
      },
      "next": "output"
    },
    {
      "name": "output",
      "type": "TcpConnector",
      "settings": {
        "address": "${BACKEND_HOST}",
        "port": ${BACKEND_PORT},
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
  "name": "direct-server-basic",
  "author": "paqet-tunnel",
  "config-version": 1,
  "core-minimum-version": 1,
  "nodes": [
    {
      "name": "input",
      "type": "TcpListener",
      "settings": {
        "address": "${LISTEN_ADDR}",
        "port": ${LISTEN_PORT},
        "nodelay": true
      },
      "next": "output"
    },
    {
      "name": "output",
      "type": "TcpConnector",
      "settings": {
        "address": "${BACKEND_HOST}",
        "port": ${BACKEND_PORT},
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
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ]
  },
  "misc": {
    "workers": 0,
    "ram-profile": "server",
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

SERVER_PUBLIC_IP="$(detect_public_ip)"
cat > "${INFO_FILE}" <<EOF
# Copy this file to the client VPS and place it at ${INFO_FILE}
format_version=${INFO_FORMAT_VERSION}
created_at=${CREATED_AT_UTC}
use_tls=${TLS_ENABLED}
tunnel_profile=${TUNNEL_PROFILE}
server_public_ip=${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}
listen_addr=${LISTEN_ADDR}
listen_port=${LISTEN_PORT}
backend_host=${BACKEND_HOST}
backend_port=${BACKEND_PORT}
grpc_service=${GRPC_SERVICE}
obfuscator_password=${OBF_PASSWORD}
tls_sni=${TLS_SNI}
EOF

echo
echo "Direct server config written: ${ROLE_CONFIG_FILE}"
echo "Active config written: ${CONFIG_FILE}"
echo "Core file written: ${CORE_FILE}"
echo "Run helper created: ${RUN_SCRIPT}"
echo "Role dir: ${ROLE_DIR}"
echo "Client info file written: ${INFO_FILE}"
echo
echo "===== COPY/PASTE COMMANDS (CLIENT VPS) ====="
echo "mkdir -p ${WATERWALL_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo "============================================="
echo
echo "Generated secrets/values:"
echo "  - tunnel_profile: ${TUNNEL_PROFILE}"
echo "  - use_tls: ${TLS_ENABLED}"
echo "  - server_public_ip: ${SERVER_PUBLIC_IP:-REPLACE_WITH_SERVER_PUBLIC_IP}"
echo "  - listen_port: ${LISTEN_PORT}"
echo "  - backend_host: ${BACKEND_HOST}"
echo "  - backend_port: ${BACKEND_PORT}"
if [ -n "${GRPC_SERVICE}" ]; then
  echo "  - grpc_service: ${GRPC_SERVICE}"
fi
if [ -n "${OBF_PASSWORD}" ]; then
  echo "  - obfuscator_password: ${OBF_PASSWORD}"
fi
if [ "${TUNNEL_PROFILE}" = "advanced" ] && [ "${TLS_ENABLED}" = "1" ]; then
  echo "  - tls_sni: ${TLS_SNI}"
  echo "  - cert_file: ${CERT_FILE}"
  echo "  - key_file: ${KEY_FILE}"
fi

sync_ufw_tunnel_rule_server "${LISTEN_PORT}"
