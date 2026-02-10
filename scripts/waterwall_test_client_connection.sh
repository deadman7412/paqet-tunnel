#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_FILE="${ROLE_DIR}/config.json"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "WaterWall Quick Tunnel Test"
echo "=========================================="
echo

if [ ! -f "${CONFIG_FILE}" ]; then
  echo -e "${RED}[ERROR] Config file not found: ${CONFIG_FILE}${NC}" >&2
  exit 1
fi

read_info() {
  local file="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub($1"=",""); print; exit}' "${file}" 2>/dev/null || true
}

parse_json_nodes() {
  local file="$1"
  python3 -c "
import json, shlex
try:
    with open('${file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    listener = next((n for n in nodes if n.get('type') == 'TcpListener'), {})
    connector = next((n for n in nodes if n.get('type') == 'TcpConnector'), {})
    lset = listener.get('settings', {}) if isinstance(listener, dict) else {}
    cset = connector.get('settings', {}) if isinstance(connector, dict) else {}
    def out(k, v):
        print(f'{k}=' + shlex.quote('' if v is None else str(v)))
    out('LISTEN_ADDR', lset.get('address', ''))
    out('LISTEN_PORT', lset.get('port', ''))
    out('CONNECT_ADDR', cset.get('address', ''))
    out('CONNECT_PORT', cset.get('port', ''))
except Exception:
    pass
" 2>/dev/null || echo ""
}

extract_ip() {
  local raw="$1"
  printf '%s\n' "${raw}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}' | head -n1
}

probe_internet_via_proxy() {
  local proxy_url="$1" endpoint body ip
  for endpoint in \
    "https://api.ipify.org?format=json" \
    "https://api.ipify.org" \
    "https://icanhazip.com"; do
    body="$(curl -fsS --connect-timeout 5 --max-time 12 --proxy "${proxy_url}" "${endpoint}" 2>/dev/null || true)"
    [ -z "${body}" ] && continue
    ip="$(extract_ip "${body}")"
    if [ -n "${ip}" ]; then
      LAST_ENDPOINT="${endpoint}"
      echo "${ip}"
      return 0
    fi
  done
  return 1
}

eval "$(parse_json_nodes "${CONFIG_FILE}")"

if [ -z "${LISTEN_ADDR:-}" ] || [ -z "${LISTEN_PORT:-}" ] || [ -z "${CONNECT_ADDR:-}" ] || [ -z "${CONNECT_PORT:-}" ]; then
  echo -e "${RED}[ERROR] Failed to parse listener/connector from ${CONFIG_FILE}${NC}" >&2
  exit 1
fi

LOCAL_ADDR="${LISTEN_ADDR}"
LOCAL_PORT="${LISTEN_PORT}"
SERVER_ADDR="${CONNECT_ADDR}"
SERVER_PORT="${CONNECT_PORT}"

EXPECTED_SERVER_IP=""
if [ -f "${INFO_FILE}" ]; then
  EXPECTED_SERVER_IP="$(read_info "${INFO_FILE}" "server_public_ip")"
  [ "${EXPECTED_SERVER_IP}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ] && EXPECTED_SERVER_IP=""
fi

echo "Local:  ${LOCAL_ADDR}:${LOCAL_PORT}"
echo "Server: ${SERVER_ADDR}:${SERVER_PORT}"
echo "Mode:   Direct forward (internet works when backend is proxy service, e.g., 3x-ui)"
echo

# Test 1: Service running
echo -n "1. Service status... "
if systemctl is-active --quiet waterwall-direct-client.service 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} Running"
else
  echo -e "${RED}[FAILURE]${NC} Not running"
  echo
  echo "Start with: systemctl start waterwall-direct-client"
  exit 1
fi

# Test 2: Local port listening
echo -n "2. Local port... "
if timeout 2 bash -c "echo test >/dev/tcp/${LOCAL_ADDR}/${LOCAL_PORT}" 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} Listening"
else
  echo -e "${RED}[FAILURE]${NC} Not listening"
  exit 1
fi

# Test 3: Server reachable
echo -n "3. Server connectivity... "
if timeout 3 bash -c "echo test >/dev/tcp/${SERVER_ADDR}/${SERVER_PORT}" 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} Reachable"
else
  echo -e "${RED}[FAILURE]${NC} Cannot reach server"
  exit 1
fi

# Test 4: Basic data flow
echo -n "4. Tunnel data flow... "
if command -v nc >/dev/null 2>&1; then
  if timeout 5 bash -c "printf 'GET / HTTP/1.0\r\n\r\n' | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null | head -n1 | grep -qiE 'HTTP/|[0-9]{3}'; then
    echo -e "${GREEN}[OK]${NC} Response received"
    RAW_TUNNEL_OK="yes"
  else
    echo -e "${YELLOW}[WARN]${NC} No HTTP-like response"
    RAW_TUNNEL_OK="partial"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} nc not installed; skipped"
  RAW_TUNNEL_OK="unknown"
fi

# Test 5: Internet egress via tunnel
INTERNET_OK="no"
INTERNET_IP=""
INTERNET_MODE=""
LAST_ENDPOINT=""

echo -n "5. Internet via tunnel... "
if command -v curl >/dev/null 2>&1; then
  if INTERNET_IP="$(probe_internet_via_proxy "http://${LOCAL_ADDR}:${LOCAL_PORT}")"; then
    INTERNET_OK="yes"
    INTERNET_MODE="http"
  elif INTERNET_IP="$(probe_internet_via_proxy "socks5h://${LOCAL_ADDR}:${LOCAL_PORT}")"; then
    INTERNET_OK="yes"
    INTERNET_MODE="socks5h"
  fi

  if [ "${INTERNET_OK}" = "yes" ]; then
    echo -e "${GREEN}[OK]${NC} ${INTERNET_IP} (mode: ${INTERNET_MODE})"
    if [ -n "${EXPECTED_SERVER_IP}" ] && [ "${EXPECTED_SERVER_IP}" != "${INTERNET_IP}" ]; then
      echo -e "   ${YELLOW}[WARN]${NC} Egress IP differs from direct_server_info (${EXPECTED_SERVER_IP})"
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Could not fetch public IP through local tunnel port"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} curl not installed; skipped"
fi

echo
echo "=========================================="
EXIT_CODE=0
if [ "${INTERNET_OK}" = "yes" ]; then
  echo -e "${GREEN}[SUCCESS]${NC} Tunnel internet egress is working via ${INTERNET_MODE} proxy mode."
elif [ "${RAW_TUNNEL_OK}" = "yes" ] || [ "${RAW_TUNNEL_OK}" = "partial" ]; then
  echo -e "${YELLOW}[WARN]${NC} Tunnel is connected, but HTTP/SOCKS internet probe failed."
  echo "   If backend protocol is VLESS/VMess/Trojan, test with a compatible client app."
  if [ "${STRICT_INTERNET_TEST:-0}" = "1" ]; then
    EXIT_CODE=1
  fi
else
  echo -e "${YELLOW}[WARN]${NC} Tunnel connectivity is partial. Check backend/proxy service."
  EXIT_CODE=1
fi
echo "=========================================="
echo

exit "${EXIT_CODE}"
