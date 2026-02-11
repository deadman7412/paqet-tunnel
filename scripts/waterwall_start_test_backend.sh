#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/server"
CONFIG_FILE="${ROLE_DIR}/config.json"

echo "=========================================="
echo "WaterWall Test Backend Server"
echo "=========================================="
echo

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Error: Server config not found at ${CONFIG_FILE}" >&2
  echo "Run server setup first!" >&2
  exit 1
fi

# Parse backend port from config
parse_json_nodes() {
  local file="$1"
  python3 -c "
import json, shlex
try:
    with open('${file}', 'r') as f:
        data = json.load(f)
    nodes = data.get('nodes', [])
    connector = next((n for n in nodes if n.get('type') == 'TcpConnector'), {})
    cset = connector.get('settings', {}) if isinstance(connector, dict) else {}
    def out(k, v):
        print(f'{k}=' + shlex.quote('' if v is None else str(v)))
    out('CONNECT_ADDR', cset.get('address', ''))
    out('CONNECT_PORT', cset.get('port', ''))
except Exception:
    pass
" 2>/dev/null || echo ""
}

eval "$(parse_json_nodes "${CONFIG_FILE}")"
BACKEND_PORT="${CONNECT_PORT}"
BACKEND_ADDR="${CONNECT_ADDR}"

if [ -z "${BACKEND_PORT}" ]; then
  echo "Error: Could not parse backend port from config" >&2
  exit 1
fi

case "${BACKEND_PORT}" in
  ''|*[!0-9]*)
    echo "Error: Parsed backend port is not numeric: ${BACKEND_PORT}" >&2
    exit 1
    ;;
esac

echo "Backend should listen on: ${BACKEND_ADDR}:${BACKEND_PORT}"
echo

# Check if port is already in use
if ss -ltn 2>/dev/null | grep -q ":${BACKEND_PORT}[[:space:]]"; then
  echo "[OK] Port ${BACKEND_PORT} is already in use!"
  echo
  echo "Process using the port:"
  ss -ltnp 2>/dev/null | grep ":${BACKEND_PORT}[[:space:]]" || lsof -i ":${BACKEND_PORT}" 2>/dev/null || echo "(Unable to determine process)"
  echo
  read -r -p "Stop existing service and start test backend? [y/N]: " STOP_EXISTING
  case "${STOP_EXISTING}" in
    y|Y|yes|YES)
      PID=$(lsof -ti ":${BACKEND_PORT}" 2>/dev/null || true)
      if [ -n "${PID}" ]; then
        echo "Stopping process ${PID}..."
        kill "${PID}" 2>/dev/null || true
        sleep 1
      fi
      ;;
    *)
      echo "Exiting. Use existing service for testing."
      exit 0
      ;;
  esac
fi

echo "Select test backend type:"
echo "1) HTTP echo server (Python) - Best for HTTP/HTTPS testing"
echo "2) HTTP file server (Python) - Shows directory listing"
echo "3) Netcat echo server - Raw TCP echo"
echo "4) SSH server - Forward to SSH"
echo "5) Custom command"
echo
read -r -p "Select option [1-5]: " BACKEND_TYPE
BACKEND_TYPE="${BACKEND_TYPE:-1}"

LOG_FILE="/tmp/waterwall_test_backend_${BACKEND_PORT}.log"

case "${BACKEND_TYPE}" in
  1)
    echo
    echo "Starting HTTP echo server on port ${BACKEND_PORT}..."
    echo "This server will echo back request details"
    echo

    # Create a simple Python HTTP echo server
    cat > /tmp/waterwall_http_echo.py <<'EOFPYTHON'
#!/usr/bin/env python3
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

class EchoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()

        response = f"""<!DOCTYPE html>
<html>
<head><title>WaterWall Test Backend</title></head>
<body style="font-family: monospace; padding: 20px;">
<h1>[SUCCESS] WaterWall Tunnel Working!</h1>
<p><strong>Request received at:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
<p><strong>Request path:</strong> {self.path}</p>
<p><strong>Client address:</strong> {self.client_address[0]}:{self.client_address[1]}</p>
<hr>
<h2>Request Headers:</h2>
<pre>{self.headers}</pre>
<hr>
<p style="color: green;">If you see this page, your WaterWall tunnel is working correctly!</p>
</body>
</html>"""
        self.wfile.write(response.encode())

    def do_POST(self):
        self.do_GET()

    def log_message(self, format, *args):
        sys.stderr.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {format % args}\n")

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('0.0.0.0', port), EchoHandler)
    print(f'HTTP Echo Server running on port {port}...')
    server.serve_forever()
EOFPYTHON
    chmod +x /tmp/waterwall_http_echo.py

    nohup python3 /tmp/waterwall_http_echo.py "${BACKEND_PORT}" > "${LOG_FILE}" 2>&1 &
    BACKEND_PID=$!
    echo "${BACKEND_PID}" > /tmp/waterwall_test_backend.pid
    ;;

  2)
    echo
    echo "Starting HTTP file server on port ${BACKEND_PORT}..."
    echo "Serving current directory"
    echo

    nohup python3 -m http.server "${BACKEND_PORT}" --bind 0.0.0.0 > "${LOG_FILE}" 2>&1 &
    BACKEND_PID=$!
    echo "${BACKEND_PID}" > /tmp/waterwall_test_backend.pid
    ;;

  3)
    echo
    echo "Starting Netcat echo server on port ${BACKEND_PORT}..."
    echo

    cat > /tmp/waterwall_nc_echo.sh <<'EOFNC'
#!/bin/bash
PORT="$1"
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n[OK] WaterWall TCP Echo - $(date)\r\nConnection working!" | nc -l "${PORT}" -q 1
  sleep 0.1
done
EOFNC
    chmod +x /tmp/waterwall_nc_echo.sh

    nohup bash /tmp/waterwall_nc_echo.sh "${BACKEND_PORT}" > "${LOG_FILE}" 2>&1 &
    BACKEND_PID=$!
    echo "${BACKEND_PID}" > /tmp/waterwall_test_backend.pid
    ;;

  4)
    echo
    echo "For SSH forwarding, SSH should already be running on port 22"
    echo "Update your WaterWall server config to forward to 127.0.0.1:22"
    echo
    if ss -ltn | grep -q ":22[[:space:]]"; then
      echo "[OK] SSH is listening on port 22"
    else
      echo "[ERROR] SSH is not running!"
    fi
    exit 0
    ;;

  5)
    echo
    read -r -p "Enter custom command to run: " CUSTOM_CMD
    if [ -z "${CUSTOM_CMD}" ]; then
      echo "No command provided, exiting."
      exit 1
    fi

    nohup bash -c "${CUSTOM_CMD}" > "${LOG_FILE}" 2>&1 &
    BACKEND_PID=$!
    echo "${BACKEND_PID}" > /tmp/waterwall_test_backend.pid
    ;;

  *)
    echo "Invalid option"
    exit 1
    ;;
esac

sleep 2

# Verify backend is running
if ss -ltn 2>/dev/null | grep -q ":${BACKEND_PORT}[[:space:]]"; then
  echo
  echo "[OK] Test backend started successfully!"
  echo
  echo "Backend PID: ${BACKEND_PID}"
  echo "Backend port: ${BACKEND_PORT}"
  echo "Log file: ${LOG_FILE}"
  echo
  echo "=== Backend is ready ==="
  echo
  echo "Test locally with:"
  echo "  curl http://127.0.0.1:${BACKEND_PORT}/"
  echo
  echo "View logs:"
  echo "  tail -f ${LOG_FILE}"
  echo
  echo "Stop backend:"
  echo "  kill ${BACKEND_PID}"
  echo "  or: kill \$(cat /tmp/waterwall_test_backend.pid)"
  echo
  echo "Now test your tunnel from the client!"
else
  echo
  echo "[ERROR] Failed to start backend on port ${BACKEND_PORT}"
  echo "Check logs: cat ${LOG_FILE}"
  exit 1
fi
