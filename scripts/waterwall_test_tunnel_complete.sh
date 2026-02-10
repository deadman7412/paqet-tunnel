#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"

echo "=========================================="
echo "WaterWall Tunnel Complete Test"
echo "=========================================="
echo

# Detect if this is server or client
if [ -f "${WATERWALL_DIR}/server/config.json" ]; then
  ROLE="server"
  ROLE_DIR="${WATERWALL_DIR}/server"
elif [ -f "${WATERWALL_DIR}/client/config.json" ]; then
  ROLE="client"
  ROLE_DIR="${WATERWALL_DIR}/client"
else
  echo "Error: No WaterWall config found in ${WATERWALL_DIR}" >&2
  exit 1
fi

echo "Detected role: ${ROLE}"
echo

# Parse config to get ports and addresses
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

CONFIG_FILE="${ROLE_DIR}/config.json"

if [ "${ROLE}" = "server" ]; then
  echo "=== Server Configuration ==="
  eval "$(parse_json_nodes "${CONFIG_FILE}")"
  BACKEND_ADDR="${CONNECT_ADDR}"
  BACKEND_PORT="${CONNECT_PORT}"

  echo "Tunnel listen: ${LISTEN_ADDR}:${LISTEN_PORT}"
  echo "Backend target: ${BACKEND_ADDR}:${BACKEND_PORT}"
  echo

  # Check if service is running
  if systemctl is-active --quiet waterwall-direct-server.service 2>/dev/null; then
    echo "[OK] WaterWall server service is running"
  else
    echo "[ERROR] WaterWall server service is NOT running!" >&2
    echo "Start it with: systemctl start waterwall-direct-server" >&2
    exit 1
  fi

  # Check if listening on tunnel port
  if ss -ltn 2>/dev/null | grep -q ":${LISTEN_PORT}[[:space:]]"; then
    echo "[OK] WaterWall is listening on tunnel port ${LISTEN_PORT}"
  else
    echo "[ERROR] WaterWall is NOT listening on port ${LISTEN_PORT}" >&2
    exit 1
  fi

  # Check if backend service is running
  echo
  echo "=== Backend Service Check ==="
  if ss -ltn 2>/dev/null | grep -q ":${BACKEND_PORT}[[:space:]]"; then
    echo "[OK] Backend service is running on port ${BACKEND_PORT}"

    # Try to connect to backend
    if timeout 3 bash -c "echo test > /dev/tcp/${BACKEND_ADDR}/${BACKEND_PORT}" 2>/dev/null; then
      echo "[OK] Backend service is reachable"
    else
      echo "[WARN] Backend port is listening but connection test failed"
    fi
  else
    echo "[ERROR] Backend service is NOT running on port ${BACKEND_PORT}!" >&2
    echo
    echo "This is why you're seeing 'Transport endpoint is not connected' errors!"
    echo
    echo "=== Solution: Start a test backend service ==="
    echo
    echo "Option 1: Simple HTTP echo server (Python):"
    echo "  python3 -m http.server ${BACKEND_PORT}"
    echo
    echo "Option 2: Netcat echo server:"
    echo "  while true; do nc -l ${BACKEND_PORT} -c 'echo HTTP/1.1 200 OK; echo; echo WaterWall Test OK'; done"
    echo
    echo "Option 3: If you have a real service (SSH, HTTP, etc):"
    echo "  Make sure it's running and listening on ${BACKEND_ADDR}:${BACKEND_PORT}"
    echo
    exit 1
  fi

  echo
  echo "=== Testing Backend Service ==="
  if command -v curl >/dev/null 2>&1; then
    echo "Testing HTTP request to backend..."
    if curl -s --connect-timeout 3 --max-time 5 "http://${BACKEND_ADDR}:${BACKEND_PORT}/" >/dev/null 2>&1; then
      echo "[OK] Backend HTTP service responds correctly"
    else
      echo "[WARN] Backend might not be HTTP service (this is OK if it's TCP/raw)"
    fi
  fi

  echo
  echo "=== Server Setup Complete ==="
  echo "Your server is ready to accept tunnel connections!"
  echo
  echo "Next step: Test from client with:"
  echo "  curl --socks5 127.0.0.1:<client_port> http://example.com"
  echo "  or use this script on the client machine"

elif [ "${ROLE}" = "client" ]; then
  echo "=== Client Configuration ==="
  eval "$(parse_json_nodes "${CONFIG_FILE}")"
  LOCAL_ADDR="${LISTEN_ADDR}"
  LOCAL_PORT="${LISTEN_PORT}"
  SERVER_ADDR="${CONNECT_ADDR}"
  SERVER_PORT="${CONNECT_PORT}"

  echo "Local listen: ${LOCAL_ADDR}:${LOCAL_PORT}"
  echo "Server target: ${SERVER_ADDR}:${SERVER_PORT}"
  echo

  # Check if service is running
  if systemctl is-active --quiet waterwall-direct-client.service 2>/dev/null; then
    echo "[OK] WaterWall client service is running"
  else
    echo "[ERROR] WaterWall client service is NOT running!" >&2
    echo "Start it with: systemctl start waterwall-direct-client" >&2
    exit 1
  fi

  # Check if listening locally
  if ss -ltn 2>/dev/null | grep -q "${LOCAL_ADDR}:${LOCAL_PORT}[[:space:]]"; then
    echo "[OK] WaterWall is listening on ${LOCAL_ADDR}:${LOCAL_PORT}"
  else
    echo "[ERROR] WaterWall is NOT listening on ${LOCAL_ADDR}:${LOCAL_PORT}" >&2
    exit 1
  fi

  # Check if server is reachable
  echo
  echo "=== Server Connectivity ==="
  if timeout 3 bash -c "echo test > /dev/tcp/${SERVER_ADDR}/${SERVER_PORT}" 2>/dev/null; then
    echo "[OK] Server is reachable at ${SERVER_ADDR}:${SERVER_PORT}"
  else
    echo "[ERROR] Cannot reach server at ${SERVER_ADDR}:${SERVER_PORT}" >&2
    echo "Check firewall rules and server status!" >&2
    exit 1
  fi

  # Try to connect through tunnel
  echo
  echo "=== Tunnel Test ==="
  echo "Attempting to connect through WaterWall tunnel..."

  if timeout 5 bash -c "echo -e 'GET / HTTP/1.0\r\n\r\n' | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null | head -n1 | grep -q "HTTP"; then
    echo "[OK] Successfully received HTTP response through tunnel!"
    echo
    echo "[SUCCESS] WaterWall tunnel is working correctly!"
    echo
    echo "=== Full Connection Path ==="
    echo "Client app → ${LOCAL_ADDR}:${LOCAL_PORT} (WaterWall client)"
    echo "         → ${SERVER_ADDR}:${SERVER_PORT} (WaterWall server)"
    echo "         → Backend service"
    echo "         → Response back through tunnel"
    echo
  elif timeout 3 bash -c "echo test | nc ${LOCAL_ADDR} ${LOCAL_PORT}" 2>/dev/null; then
    echo "[PARTIAL] Connection to tunnel succeeded, but no response received"
    echo
    echo "This could mean:"
    echo "  1. Backend service on server is not running"
    echo "  2. Backend service is not HTTP (check server logs)"
    echo "  3. Backend service exists but doesn't respond to simple requests"
    echo
    echo "Check server logs with:"
    echo "  ssh <server> 'journalctl -u waterwall-direct-server -n 50'"
  else
    echo "[ERROR] Failed to connect through tunnel" >&2
    echo
    echo "Check server logs to see what's happening:"
    echo "  ssh <server> 'journalctl -u waterwall-direct-server -n 50'"
    echo
    echo "Common issues:"
    echo "  1. Backend service not running on server"
    echo "  2. Backend port mismatch"
    echo "  3. Firewall blocking traffic"
  fi

  echo
  echo "=== Additional Tests You Can Run ==="
  echo
  echo "Test with netcat (raw TCP):"
  echo "  echo 'test' | nc ${LOCAL_ADDR} ${LOCAL_PORT}"
  echo
  echo "Test with telnet:"
  echo "  telnet ${LOCAL_ADDR} ${LOCAL_PORT}"
  echo
  echo "Watch live tunnel activity:"
  echo "  journalctl -u waterwall-direct-client -f"
  echo
fi

echo
echo "=========================================="
echo "Test Complete"
echo "=========================================="
