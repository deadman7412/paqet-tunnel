#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "WaterWall Complete Test Report"
echo "=========================================="
echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo

# Detect if this is server or client
if [ -f "${WATERWALL_DIR}/server/config.json" ]; then
  ROLE="server"
  ROLE_DIR="${WATERWALL_DIR}/server"
  SERVICE_NAME="waterwall-direct-server"
elif [ -f "${WATERWALL_DIR}/client/config.json" ]; then
  ROLE="client"
  ROLE_DIR="${WATERWALL_DIR}/client"
  SERVICE_NAME="waterwall-direct-client"
else
  echo -e "${RED}[ERROR] No WaterWall config found in ${WATERWALL_DIR}${NC}" >&2
  exit 1
fi

echo -e "${CYAN}=== SYSTEM INFORMATION ===${NC}"
echo "Role: ${ROLE}"
echo "Hostname: $(hostname)"

# Try multiple IP detection services
PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || true)
  [ -z "${PUBLIC_IP}" ] && PUBLIC_IP=$(curl -s --max-time 3 https://icanhazip.com 2>/dev/null || true)
  [ -z "${PUBLIC_IP}" ] && PUBLIC_IP=$(curl -s --max-time 3 https://ipecho.net/plain 2>/dev/null || true)
fi
[ -z "${PUBLIC_IP}" ] && PUBLIC_IP="Unable to detect"
echo "Public IP: ${PUBLIC_IP}"

echo "OS: $(uname -s) $(uname -r)"
echo "Architecture: $(uname -m)"
echo

# Parse config to get ports and addresses
parse_json_nodes() {
  local file="$1"
  # Extract the nodes array and parse first and second node
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

CONFIG_FILE="${ROLE_DIR}/config.json"
CORE_FILE="${ROLE_DIR}/core.json"

echo -e "${CYAN}=== WATERWALL INSTALLATION ===${NC}"
if [ -x "${WATERWALL_DIR}/waterwall" ]; then
  WW_VERSION=$("${WATERWALL_DIR}/waterwall" --version 2>/dev/null | head -n1 || echo "Unknown")
  echo -e "${GREEN}[OK]${NC} WaterWall binary found: ${WATERWALL_DIR}/waterwall"
  echo "     Version: ${WW_VERSION}"
else
  echo -e "${RED}[ERROR]${NC} WaterWall binary not found or not executable"
fi
echo

echo -e "${CYAN}=== CONFIGURATION FILES ===${NC}"
if [ -f "${CONFIG_FILE}" ]; then
  echo -e "${GREEN}[OK]${NC} Config file exists: ${CONFIG_FILE}"
  echo "     Size: $(stat -f%z "${CONFIG_FILE}" 2>/dev/null || stat -c%s "${CONFIG_FILE}" 2>/dev/null) bytes"
else
  echo -e "${RED}[ERROR]${NC} Config file missing: ${CONFIG_FILE}"
fi

if [ -f "${CORE_FILE}" ]; then
  echo -e "${GREEN}[OK]${NC} Core file exists: ${CORE_FILE}"
else
  echo -e "${RED}[ERROR]${NC} Core file missing: ${CORE_FILE}"
fi
echo

if [ "${ROLE}" = "server" ]; then
  echo -e "${CYAN}=== SERVER CONFIGURATION ===${NC}"

  # Parse config using Python for accurate JSON parsing
  eval "$(parse_json_nodes "${CONFIG_FILE}")"

  echo "Tunnel listen: ${LISTEN_ADDR}:${LISTEN_PORT}"
  echo "Backend target: ${CONNECT_ADDR}:${CONNECT_PORT}"

  # Store for later use
  BACKEND_ADDR="${CONNECT_ADDR}"
  BACKEND_PORT="${CONNECT_PORT}"
  echo

  echo -e "${CYAN}=== SERVICE STATUS ===${NC}"
  if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} WaterWall service is running"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -n 3
  else
    echo -e "${RED}[ERROR]${NC} WaterWall service is NOT running"
    echo "     Status: $(systemctl is-active "${SERVICE_NAME}.service" 2>/dev/null || echo "inactive")"
  fi
  echo

  echo -e "${CYAN}=== PORT LISTENING STATUS ===${NC}"
  if ss -ltn 2>/dev/null | grep -q ":${LISTEN_PORT}[[:space:]]"; then
    echo -e "${GREEN}[OK]${NC} WaterWall is listening on tunnel port ${LISTEN_PORT}"
    ss -ltnp 2>/dev/null | grep ":${LISTEN_PORT}[[:space:]]" | head -n1
  else
    echo -e "${RED}[ERROR]${NC} WaterWall is NOT listening on port ${LISTEN_PORT}"
  fi
  echo

  echo -e "${CYAN}=== BACKEND SERVICE STATUS ===${NC}"
  if ss -ltn 2>/dev/null | grep -q ":${BACKEND_PORT}[[:space:]]"; then
    echo -e "${GREEN}[OK]${NC} Backend service is running on port ${BACKEND_PORT}"
    ss -ltnp 2>/dev/null | grep ":${BACKEND_PORT}[[:space:]]" | head -n1

    # Try to connect to backend
    if timeout 3 bash -c "echo test > /dev/tcp/${BACKEND_ADDR}/${BACKEND_PORT}" 2>/dev/null; then
      echo -e "${GREEN}[OK]${NC} Backend service is reachable"
    else
      echo -e "${YELLOW}[WARN]${NC} Backend port is listening but connection test failed"
    fi
  else
    echo -e "${RED}[ERROR]${NC} Backend service is NOT running on port ${BACKEND_PORT}"
    echo -e "${YELLOW}     This is why you see 'Transport endpoint is not connected' errors!${NC}"
    echo "     Start backend with: menu → Server menu → Option 6"
  fi
  echo

  echo -e "${CYAN}=== FIREWALL STATUS ===${NC}"
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
      echo -e "${GREEN}[OK]${NC} UFW is active"
      if ufw status | grep -q "${LISTEN_PORT}/tcp"; then
        echo -e "${GREEN}[OK]${NC} Tunnel port ${LISTEN_PORT}/tcp is allowed in UFW"
      else
        echo -e "${YELLOW}[WARN]${NC} Tunnel port ${LISTEN_PORT}/tcp is NOT in UFW rules"
      fi
    else
      echo -e "${YELLOW}[INFO]${NC} UFW is installed but not active"
    fi
  else
    echo -e "${YELLOW}[INFO]${NC} UFW is not installed"
  fi
  echo

  echo -e "${CYAN}=== RECENT LOGS (last 10 lines) ===${NC}"
  journalctl -u "${SERVICE_NAME}.service" -n 10 --no-pager 2>/dev/null || echo "Unable to read logs"
  echo

elif [ "${ROLE}" = "client" ]; then
  echo -e "${CYAN}=== CLIENT CONFIGURATION ===${NC}"

  # Parse config using Python for accurate JSON parsing
  eval "$(parse_json_nodes "${CONFIG_FILE}")"

  LOCAL_ADDR="${LISTEN_ADDR}"
  LOCAL_PORT="${LISTEN_PORT}"
  SERVER_ADDR="${CONNECT_ADDR}"
  SERVER_PORT="${CONNECT_PORT}"

  echo "Local listen: ${LOCAL_ADDR}:${LOCAL_PORT}"
  echo "Server target: ${SERVER_ADDR}:${SERVER_PORT}"
  echo

  echo -e "${CYAN}=== SERVICE STATUS ===${NC}"
  if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} WaterWall service is running"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -n 3
  else
    echo -e "${RED}[ERROR]${NC} WaterWall service is NOT running"
    echo "     Status: $(systemctl is-active "${SERVICE_NAME}.service" 2>/dev/null || echo "inactive")"
  fi
  echo

  echo -e "${CYAN}=== PORT LISTENING STATUS ===${NC}"
  if ss -ltn 2>/dev/null | grep -q "${LOCAL_ADDR}:${LOCAL_PORT}[[:space:]]"; then
    echo -e "${GREEN}[OK]${NC} WaterWall is listening on ${LOCAL_ADDR}:${LOCAL_PORT}"
    ss -ltnp 2>/dev/null | grep "${LOCAL_ADDR}:${LOCAL_PORT}[[:space:]]" | head -n1
  else
    echo -e "${RED}[ERROR]${NC} WaterWall is NOT listening on ${LOCAL_ADDR}:${LOCAL_PORT}"
  fi
  echo

  echo -e "${CYAN}=== SERVER CONNECTIVITY ===${NC}"
  if timeout 3 bash -c "echo test > /dev/tcp/${SERVER_ADDR}/${SERVER_PORT}" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Server is reachable at ${SERVER_ADDR}:${SERVER_PORT}"
  else
    echo -e "${RED}[ERROR]${NC} Cannot reach server at ${SERVER_ADDR}:${SERVER_PORT}"
    echo "     Check: Server is running, firewall allows traffic"
  fi
  echo

  echo -e "${CYAN}=== TUNNEL FUNCTIONALITY TEST ===${NC}"
  echo "Testing connection through tunnel..."

  if timeout 5 bash -c "echo -e 'GET / HTTP/1.0\r\n\r\n' | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null | head -n1 | grep -q "HTTP"; then
    echo -e "${GREEN}[OK]${NC} Successfully received HTTP response through tunnel!"
    echo -e "${GREEN}[SUCCESS] WaterWall tunnel is WORKING CORRECTLY!${NC}"
  elif timeout 3 bash -c "echo test | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null; then
    echo -e "${YELLOW}[PARTIAL]${NC} Connection succeeded but no HTTP response"
    echo "     Backend may not be HTTP service or not running"
  else
    echo -e "${RED}[ERROR]${NC} Failed to connect through tunnel"
    echo "     Check server logs and backend service"
  fi
  echo

  echo -e "${CYAN}=== FIREWALL STATUS ===${NC}"
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
      echo -e "${GREEN}[OK]${NC} UFW is active"
      if ufw status | grep -q "waterwall-tunnel"; then
        echo -e "${GREEN}[OK]${NC} WaterWall tunnel rule found in UFW"
      else
        echo -e "${YELLOW}[WARN]${NC} No WaterWall-specific UFW rules found"
      fi
    else
      echo -e "${YELLOW}[INFO]${NC} UFW is installed but not active"
    fi
  else
    echo -e "${YELLOW}[INFO]${NC} UFW is not installed"
  fi
  echo

  echo -e "${CYAN}=== RECENT LOGS (last 10 lines) ===${NC}"
  journalctl -u "${SERVICE_NAME}.service" -n 10 --no-pager 2>/dev/null || echo "Unable to read logs"
  echo
fi

echo -e "${CYAN}=== DNS CONFIGURATION ===${NC}"
if [ -f "${CORE_FILE}" ]; then
  DNS_SERVERS=$(grep -A 5 '"dns"' "${CORE_FILE}" | grep -o '"[0-9.]*"' | tr -d '"' | grep -E '^[0-9.]+$' || echo "none")
  if [ "${DNS_SERVERS}" != "none" ]; then
    echo -e "${GREEN}[OK]${NC} DNS servers configured:"
    echo "${DNS_SERVERS}" | while read -r dns; do
      [ -n "${dns}" ] && echo "     - ${dns}"
    done
  else
    echo -e "${YELLOW}[WARN]${NC} No DNS servers configured (using system default)"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} Cannot check DNS config - core file not found"
fi
echo

echo -e "${CYAN}=== NETWORK STATISTICS ===${NC}"
if command -v ss >/dev/null 2>&1; then
  ESTABLISHED=$(ss -tn 2>/dev/null | grep -c ESTAB || echo 0)
  LISTENING=$(ss -ltn 2>/dev/null | grep -c LISTEN || echo 0)
  echo "Established connections: ${ESTABLISHED}"
  echo "Listening sockets: ${LISTENING}"
else
  echo "ss command not available"
fi
echo

echo "=========================================="
echo -e "${CYAN}TEST SUMMARY${NC}"
echo "=========================================="
echo "Role: ${ROLE}"
echo "Config file: $([ -f "${CONFIG_FILE}" ] && echo "[OK]" || echo "[FAIL]")"
echo "Service running: $(systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null && echo "[OK]" || echo "[FAIL]")"

if [ "${ROLE}" = "server" ]; then
  echo "Tunnel listening: $(ss -ltn 2>/dev/null | grep -q ":${LISTEN_PORT}[[:space:]]" && echo "[OK]" || echo "[FAIL]")"
  echo "Backend running: $(ss -ltn 2>/dev/null | grep -q ":${BACKEND_PORT}[[:space:]]" && echo "[OK]" || echo "[FAIL]")"
else
  echo "Local listening: $(ss -ltn 2>/dev/null | grep -q "${LOCAL_ADDR}:${LOCAL_PORT}[[:space:]]" && echo "[OK]" || echo "[FAIL]")"
  echo "Server reachable: $(timeout 3 bash -c "echo test > /dev/tcp/${SERVER_ADDR}/${SERVER_PORT}" 2>/dev/null && echo "[OK]" || echo "[FAIL]")"
fi

echo
echo "=========================================="
echo "Report complete. Share this output for analysis."
echo "=========================================="
