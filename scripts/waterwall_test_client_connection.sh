#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_FILE="${ROLE_DIR}/config.json"
SERVICE_NAME="waterwall-direct-client"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Client config not found: ${CONFIG_FILE}" >&2
  echo "Run Waterwall client setup first." >&2
  exit 1
fi

extract_port_by_type() {
  local node_type="$1"
  awk -v t="${node_type}" '
    /"type"[[:space:]]*:[[:space:]]*"/ {
      if (index($0, "\"" t "\"")) {
        in_node=1
      }
    }
    in_node && /"port"[[:space:]]*:[[:space:]]*[0-9]+/ {
      gsub(/[^0-9]/, "", $0)
      if ($0 != "") { print $0; exit }
    }
    in_node && /}/ { in_node=0 }
  ' "${CONFIG_FILE}" 2>/dev/null || true
}

extract_addr_by_type() {
  local node_type="$1"
  awk -v t="${node_type}" '
    /"type"[[:space:]]*:[[:space:]]*"/ {
      if (index($0, "\"" t "\"")) {
        in_node=1
      }
    }
    in_node && /"address"[[:space:]]*:[[:space:]]*"/ {
      gsub(/.*"address"[[:space:]]*:[[:space:]]*"/, "", $0)
      gsub(/".*/, "", $0)
      print $0
      exit
    }
    in_node && /}/ { in_node=0 }
  ' "${CONFIG_FILE}" 2>/dev/null || true
}

can_connect_tcp() {
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 3 "${host}" "${port}" >/dev/null 2>&1
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 bash -c "echo > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    return $?
  fi
  bash -c "echo > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

LISTEN_ADDR="$(extract_addr_by_type "TcpListener")"
LISTEN_PORT="$(extract_port_by_type "TcpListener")"
FOREIGN_ADDR="$(extract_addr_by_type "TcpConnector")"
FOREIGN_PORT="$(extract_port_by_type "TcpConnector")"

if [ -z "${LISTEN_ADDR}" ]; then
  LISTEN_ADDR="127.0.0.1"
fi

echo "Waterwall client test"
echo "---------------------"
echo "Config:       ${CONFIG_FILE}"
echo "Local listen: ${LISTEN_ADDR}:${LISTEN_PORT:-unknown}"
echo "Server target:${FOREIGN_ADDR:-unknown}:${FOREIGN_PORT:-unknown}"
echo

FAILED=0

if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "[OK] Service is active: ${SERVICE_NAME}"
  else
    echo "[FAIL] Service is not active: ${SERVICE_NAME}"
    FAILED=1
  fi
else
  echo "[WARN] systemctl not found; skipping service status check."
fi

if [ -z "${LISTEN_PORT}" ]; then
  echo "[FAIL] Could not detect local listen port from config."
  FAILED=1
else
  if can_connect_tcp "${LISTEN_ADDR}" "${LISTEN_PORT}"; then
    echo "[OK] Local Waterwall listener is reachable: ${LISTEN_ADDR}:${LISTEN_PORT}"
  else
    echo "[FAIL] Local Waterwall listener is not reachable: ${LISTEN_ADDR}:${LISTEN_PORT}"
    FAILED=1
  fi
fi

if [ -z "${FOREIGN_ADDR}" ] || [ -z "${FOREIGN_PORT}" ]; then
  echo "[WARN] Could not detect foreign server address/port from config."
else
  if can_connect_tcp "${FOREIGN_ADDR}" "${FOREIGN_PORT}"; then
    echo "[OK] Foreign server is reachable: ${FOREIGN_ADDR}:${FOREIGN_PORT}"
  else
    echo "[FAIL] Foreign server is not reachable: ${FOREIGN_ADDR}:${FOREIGN_PORT}"
    FAILED=1
  fi
fi

echo
if [ "${FAILED}" -eq 0 ]; then
  echo "Success: Waterwall client checks passed."
  exit 0
fi

echo "Failed: one or more Waterwall client checks did not pass." >&2
echo "Hint: check both sides with Service control and review logs." >&2
exit 1
