#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
CLIENT_CONFIG_FILE="${ICMPTUNNEL_DIR}/client/config.json"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "${CLIENT_CONFIG_FILE}" ]; then
  echo -e "${RED}[ERROR]${NC} Client config not found: ${CLIENT_CONFIG_FILE}" >&2
  echo "Run client setup first." >&2
  exit 1
fi

# Parse config
eval "$(python3 -c "
import json
try:
    with open('${CLIENT_CONFIG_FILE}', 'r') as f:
        data = json.load(f)
    print('SERVER_IP=' + str(data.get('server', '')))
    print('SOCKS_PORT=' + str(data.get('listen_port_socks', '')))
except:
    pass
" 2>/dev/null || echo "")"

if [ -z "${SERVER_IP}" ] || [ -z "${SOCKS_PORT}" ]; then
  echo -e "${RED}[ERROR]${NC} Could not parse config." >&2
  exit 1
fi

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}ICMP Tunnel Client Connection Test${NC}"
echo -e "${BLUE}===================================${NC}"
echo

# Test 1: ICMP reachability to server
echo -e "${BLUE}[1/4]${NC} Testing ICMP reachability to server (${SERVER_IP})..."
if ping -c 3 -W 2 "${SERVER_IP}" >/dev/null 2>&1; then
  echo -e "${GREEN}[SUCCESS]${NC} Server is reachable via ICMP"
else
  echo -e "${RED}[FAILURE]${NC} Cannot ping server - check network or firewall"
  echo "Tip: Ensure server allows ICMP from this client IP"
fi
echo

# Test 2: Check SOCKS proxy listening
echo -e "${BLUE}[2/4]${NC} Checking SOCKS5 proxy listening on port ${SOCKS_PORT}..."
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${SOCKS_PORT}$" >/dev/null 2>&1; then
  echo -e "${GREEN}[SUCCESS]${NC} SOCKS5 proxy is listening on port ${SOCKS_PORT}"
else
  echo -e "${RED}[FAILURE]${NC} SOCKS5 proxy is NOT listening on port ${SOCKS_PORT}"
  echo "Tip: Start the icmptunnel-client service"
fi
echo

# Test 3: Check service status
echo -e "${BLUE}[3/4]${NC} Checking icmptunnel-client service status..."
if systemctl is-active --quiet icmptunnel-client.service 2>/dev/null; then
  echo -e "${GREEN}[SUCCESS]${NC} icmptunnel-client service is active"
else
  echo -e "${YELLOW}[WARN]${NC} icmptunnel-client service is not active"
  echo "Tip: Install and start the service via menu"
fi
echo

# Test 4: Test SOCKS proxy with curl
echo -e "${BLUE}[4/4]${NC} Testing SOCKS5 proxy with HTTP request..."
if command -v curl >/dev/null 2>&1; then
  if curl -x socks5://127.0.0.1:${SOCKS_PORT} -I --connect-timeout 5 --max-time 10 https://www.google.com 2>/dev/null | head -n1 | grep -q "HTTP"; then
    echo -e "${GREEN}[SUCCESS]${NC} SOCKS5 proxy is working - internet egress OK"
  else
    echo -e "${RED}[FAILURE]${NC} SOCKS5 proxy test failed"
    echo "Tip: Check server-side tunnel and backend configuration"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} curl not available - skipping SOCKS test"
fi
echo

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}===================================${NC}"
echo "Server IP: ${SERVER_IP}"
echo "SOCKS Port: ${SOCKS_PORT}"
echo
echo "To view service logs:"
echo "  sudo journalctl -u icmptunnel-client.service -n 50"
