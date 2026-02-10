#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_FILE="${ROLE_DIR}/config.json"

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

# Parse config using Python for accurate JSON parsing
parse_json_nodes() {
  local file="$1"
  python3 -c "
import json, sys
try:
    with open('${file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    if len(nodes) >= 2:
        listener = nodes[0].get('settings', {})
        connector = nodes[1].get('settings', {})
        print('LISTEN_ADDR=' + str(listener.get('address', '')))
        print('LISTEN_PORT=' + str(listener.get('port', '')))
        print('CONNECT_ADDR=' + str(connector.get('address', '')))
        print('CONNECT_PORT=' + str(connector.get('port', '')))
except:
    pass
" 2>/dev/null || echo ""
}

eval "$(parse_json_nodes "${CONFIG_FILE}")"
LOCAL_ADDR="${LISTEN_ADDR}"
LOCAL_PORT="${LISTEN_PORT}"
SERVER_ADDR="${CONNECT_ADDR}"
SERVER_PORT="${CONNECT_PORT}"

echo "Local:  ${LOCAL_ADDR}:${LOCAL_PORT}"
echo "Server: ${SERVER_ADDR}:${SERVER_PORT}"
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

# Test 4: Tunnel functionality
echo -n "4. Tunnel data flow... "
if timeout 5 bash -c "echo -e 'GET / HTTP/1.0\r\n\r\n' | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null | head -n1 | grep -q "HTTP"; then
  echo -e "${GREEN}[OK]${NC} Working"
  TUNNEL_WORKS="yes"
else
  echo -e "${YELLOW}[WARN]${NC} No HTTP response"
  TUNNEL_WORKS="partial"
fi

echo
echo "=========================================="
if [ "${TUNNEL_WORKS}" = "yes" ]; then
  echo -e "${GREEN}[SUCCESS]${NC} Tunnel is fully operational!"
else
  echo -e "${YELLOW}[WARN]${NC} Tunnel connects but backend may not be HTTP"
  echo "   This is OK for non-HTTP services (TCP forwarding, etc.)"
fi
echo "=========================================="
echo
