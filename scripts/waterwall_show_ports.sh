#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_FILE="${ROLE_DIR}/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "WaterWall Client Port Configuration"
echo "=========================================="
echo

if [ ! -f "${CONFIG_FILE}" ]; then
  echo -e "${RED}[ERROR]${NC} Config file not found: ${CONFIG_FILE}" >&2
  echo "Run client setup first!" >&2
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
SERVICE_PORT="${LISTEN_PORT}"
TUNNEL_PORT="${CONNECT_PORT}"
SERVER_IP="${CONNECT_ADDR}"

if [ -z "${SERVICE_PORT}" ] || [ -z "${TUNNEL_PORT}" ]; then
  echo -e "${RED}[ERROR]${NC} Could not parse ports from config" >&2
  exit 1
fi

echo -e "${CYAN}=== PORT INFORMATION ===${NC}"
echo
echo -e "${GREEN}Service Port (Local):${NC} ${SERVICE_PORT}"
echo "  - This is where your applications connect"
echo "  - Use this port in your proxy/VPN client config"
echo "  - Example: SOCKS5 proxy at 127.0.0.1:${SERVICE_PORT}"
echo
echo -e "${GREEN}Tunnel Port (Remote):${NC} ${TUNNEL_PORT}"
echo "  - This is the port on the server that the client connects to"
echo "  - Server IP: ${SERVER_IP}"
echo "  - Full tunnel endpoint: ${SERVER_IP}:${TUNNEL_PORT}"
echo
echo "=========================================="
echo -e "${CYAN}=== CONFIGURATION EXAMPLES ===${NC}"
echo "=========================================="
echo
echo -e "${BLUE}1. Direct SOCKS5 Proxy:${NC}"
echo "   Server: 127.0.0.1"
echo "   Port: ${SERVICE_PORT}"
echo "   Type: SOCKS5"
echo
echo -e "${BLUE}2. Browser Proxy Settings:${NC}"
echo "   SOCKS Host: 127.0.0.1"
echo "   SOCKS Port: ${SERVICE_PORT}"
echo "   SOCKS v5: Yes"
echo
echo -e "${BLUE}3. ProxyChains4 Config:${NC}"
echo "   [ProxyList]"
echo "   socks5 127.0.0.1 ${SERVICE_PORT}"
echo
echo -e "${BLUE}4. cURL with Tunnel:${NC}"
echo "   curl --socks5 127.0.0.1:${SERVICE_PORT} https://ipinfo.io/ip"
echo
echo -e "${BLUE}5. SSH through Tunnel:${NC}"
echo "   ssh -o ProxyCommand=\"nc -X 5 -x 127.0.0.1:${SERVICE_PORT} %h %p\" user@destination"
echo
echo "=========================================="
echo -e "${YELLOW}Note:${NC} Service port ${SERVICE_PORT} should be open in UFW for local connections."
echo "      Tunnel port ${TUNNEL_PORT} is used for outbound connection to server only."
echo "=========================================="
echo
