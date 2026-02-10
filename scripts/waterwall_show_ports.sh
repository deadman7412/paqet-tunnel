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
import json, shlex
try:
    with open('${file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    listener = next((n for n in nodes if n.get('type') == 'TcpListener'), {})
    connector = next((n for n in nodes if n.get('type') == 'TcpConnector'), {})
    node_types = {str(n.get('type', '')) for n in nodes}
    lset = listener.get('settings', {}) if isinstance(listener, dict) else {}
    cset = connector.get('settings', {}) if isinstance(connector, dict) else {}
    def out(k, v):
        print(f'{k}=' + shlex.quote('' if v is None else str(v)))
    out('LISTEN_ADDR', lset.get('address', ''))
    out('LISTEN_PORT', lset.get('port', ''))
    out('CONNECT_ADDR', cset.get('address', ''))
    out('CONNECT_PORT', cset.get('port', ''))
    out('HAS_PROXY_CLIENT', '1' if 'ProxyClient' in node_types else '0')
except Exception:
    pass
" 2>/dev/null || echo ""
}

eval "$(parse_json_nodes "${CONFIG_FILE}")"
SERVICE_PORT="${LISTEN_PORT}"
TUNNEL_PORT="${CONNECT_PORT}"
SERVER_IP="${CONNECT_ADDR}"
HAS_PROXY_CLIENT="${HAS_PROXY_CLIENT:-0}"

if [ -z "${SERVICE_PORT}" ] || [ -z "${TUNNEL_PORT}" ]; then
  echo -e "${RED}[ERROR]${NC} Could not parse ports from config" >&2
  exit 1
fi

echo -e "${CYAN}=== PORT INFORMATION ===${NC}"
echo
echo -e "${GREEN}Service Port (Local):${NC} ${SERVICE_PORT}"
echo "  - This is where your applications/users connect"
echo "  - Client listens on: ${LISTEN_ADDR}:${SERVICE_PORT}"
echo "  - Access from internet: <CLIENT_PUBLIC_IP>:${SERVICE_PORT}"
echo "  - Access locally: 127.0.0.1:${SERVICE_PORT}"
echo
echo -e "${GREEN}Tunnel Port (Remote):${NC} ${TUNNEL_PORT}"
echo "  - This is the port on the server that the client connects to"
echo "  - Server IP: ${SERVER_IP}"
echo "  - Full tunnel endpoint: ${SERVER_IP}:${TUNNEL_PORT}"
echo
echo "=========================================="
echo -e "${CYAN}=== USAGE INFORMATION ===${NC}"
echo "=========================================="
echo
if [ "${HAS_PROXY_CLIENT}" = "1" ]; then
  echo -e "${GREEN}Proxy mode detected:${NC} ProxyClient is enabled in client config."
  echo
  echo -e "${BLUE}Use Case 1: HTTP proxy from client VPS${NC}"
  echo "   curl --proxy http://127.0.0.1:${SERVICE_PORT} https://api.ipify.org"
  echo
  echo -e "${BLUE}Use Case 2: SOCKS5 proxy from client VPS${NC}"
  echo "   curl --proxy socks5h://127.0.0.1:${SERVICE_PORT} https://api.ipify.org"
  echo
  echo -e "${BLUE}Use Case 3: Desktop/mobile proxy apps${NC}"
  echo "   Proxy host: <CLIENT_PUBLIC_IP>"
  echo "   Proxy port: ${SERVICE_PORT}"
  echo "   Protocol: HTTP or SOCKS5"
else
  echo -e "${YELLOW}Forward mode detected:${NC} This is a TCP forward tunnel (fixed backend)."
  echo
  echo -e "${BLUE}Use Case 1: Local Testing (from client VPS)${NC}"
  echo "   curl http://127.0.0.1:${SERVICE_PORT}/"
  echo
  echo -e "${BLUE}Use Case 2: With 3x-ui/Xray Proxy${NC}"
  echo "   1. Install 3x-ui on server VPS"
  echo "   2. Configure inbound on server backend port"
  echo "   3. Connect clients to <CLIENT_PUBLIC_IP>:${SERVICE_PORT}"
  echo
  echo -e "${BLUE}Use Case 3: SSH Access${NC}"
  echo "   1. Change server backend port to 22 (SSH port)"
  echo "   2. From client VPS: ssh -p ${SERVICE_PORT} user@127.0.0.1"
  echo
  echo -e "${BLUE}Use Case 4: Database Access${NC}"
  echo "   1. Set server backend to database port (e.g., 3306)"
  echo "   2. From client VPS: mysql -h 127.0.0.1 -P ${SERVICE_PORT}"
fi
echo
echo "=========================================="
echo -e "${YELLOW}Note:${NC} Service port ${SERVICE_PORT} should be open in UFW for local connections."
echo "      Tunnel port ${TUNNEL_PORT} is used for outbound connection to server only."
echo "=========================================="
echo
