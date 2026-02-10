#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
ROLE_DIR="${WATERWALL_DIR}/client"
CONFIG_FILE="${ROLE_DIR}/config.json"
INFO_FILE="${WATERWALL_DIR}/direct_server_info.txt"
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

detect_active_listen_port() {
  if ! command -v ss >/dev/null 2>&1; then
    return 0
  fi
  ss -lntp 2>/dev/null | awk '/waterwall/ && /127\.0\.0\.1:/ {
    if (match($4, /127\.0\.0\.1:([0-9]+)/, m)) {
      print m[1]; exit
    }
  }'
}

extract_ip_from_json() {
  local payload="$1"
  echo "${payload}" | sed -nE 's/.*"origin"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p; s/.*"ip"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1
}

read_info() {
  local file="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub($1"=",""); print; exit}' "${file}" 2>/dev/null || true
}

fetch_public_ip_direct() {
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  local body=""
  body="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ipify.org?format=json 2>/dev/null || true)"
  if [ -n "${body}" ]; then
    extract_ip_from_json "${body}"
    return 0
  fi
  body="$(curl -fsSL --connect-timeout 5 --max-time 10 https://httpbin.org/ip 2>/dev/null || true)"
  [ -n "${body}" ] || return 1
  extract_ip_from_json "${body}"
}

fetch_public_ip_via_proxy() {
  local proxy_mode="$1"
  local host="$2"
  local port="$3"
  local body=""
  local ip=""
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  if [ "${proxy_mode}" = "socks5" ]; then
    body="$(curl -fsSL --connect-timeout 6 --max-time 12 --proxy "socks5h://${host}:${port}" https://api.ipify.org?format=json 2>/dev/null || true)"
    [ -z "${body}" ] && body="$(curl -fsSL --connect-timeout 6 --max-time 12 --proxy "socks5h://${host}:${port}" https://httpbin.org/ip 2>/dev/null || true)"
  elif [ "${proxy_mode}" = "http" ]; then
    body="$(curl -fsSL --connect-timeout 6 --max-time 12 --proxy "http://${host}:${port}" https://api.ipify.org?format=json 2>/dev/null || true)"
    [ -z "${body}" ] && body="$(curl -fsSL --connect-timeout 6 --max-time 12 --proxy "http://${host}:${port}" https://httpbin.org/ip 2>/dev/null || true)"
  fi

  [ -n "${body}" ] || return 1
  ip="$(extract_ip_from_json "${body}")"
  [ -n "${ip}" ] || return 1
  echo "${ip}"
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
    ACTIVE_PORT="$(detect_active_listen_port || true)"
    if [ -n "${ACTIVE_PORT}" ] && [ "${ACTIVE_PORT}" != "${LISTEN_PORT}" ]; then
      echo "[WARN] Config/runtime mismatch:"
      echo "      config expects ${LISTEN_ADDR}:${LISTEN_PORT}, but running service listens on 127.0.0.1:${ACTIVE_PORT}"
      echo "      Reinstall/restart Waterwall client service to load latest config."
    else
      echo "[FAIL] Local Waterwall listener is not reachable: ${LISTEN_ADDR}:${LISTEN_PORT}"
      FAILED=1
    fi
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

if [ -f "${INFO_FILE}" ]; then
  B_HOST="$(read_info "${INFO_FILE}" "backend_host")"
  B_PORT="$(read_info "${INFO_FILE}" "backend_port")"
  if [ -n "${B_HOST}" ] || [ -n "${B_PORT}" ]; then
    echo "[INFO] Server backend target from info file: ${B_HOST:-unknown}:${B_PORT:-unknown}"
  fi
fi

if command -v curl >/dev/null 2>&1; then
  DIRECT_IP="$(fetch_public_ip_direct || true)"
  if [ -n "${DIRECT_IP}" ]; then
    echo "[INFO] Direct public IP (no tunnel): ${DIRECT_IP}"
  else
    echo "[WARN] Could not determine direct public IP."
  fi

  read -r -p "Run proxy-mode reported IP test via local Waterwall port? [y/N]: " RUN_PROXY_IP_TEST
  case "${RUN_PROXY_IP_TEST:-N}" in
    y|Y|yes|YES)
      if [ -n "${LISTEN_PORT}" ]; then
        TUNNEL_IP_SOCKS="$(fetch_public_ip_via_proxy socks5 "${LISTEN_ADDR}" "${LISTEN_PORT}" || true)"
        TUNNEL_IP_HTTP="$(fetch_public_ip_via_proxy http "${LISTEN_ADDR}" "${LISTEN_PORT}" || true)"
        if [ -n "${TUNNEL_IP_SOCKS}" ]; then
          echo "[OK] Reported public IP via Waterwall (SOCKS5): ${TUNNEL_IP_SOCKS}"
        elif [ -n "${TUNNEL_IP_HTTP}" ]; then
          echo "[OK] Reported public IP via Waterwall (HTTP proxy): ${TUNNEL_IP_HTTP}"
        else
          echo "[FAIL] Could not fetch reported IP via Waterwall local port ${LISTEN_ADDR}:${LISTEN_PORT}."
          echo "[FAIL] If backend is not an HTTP/SOCKS proxy, skip this specific test."
          FAILED=1
        fi
      fi
      ;;
    *)
      echo "[INFO] Skipped proxy-mode reported IP test."
      ;;
  esac
else
  echo "[WARN] curl not found; skipped reported public IP test."
fi

echo
if [ "${FAILED}" -eq 0 ]; then
  echo "Success: Waterwall client checks passed."
  exit 0
fi

echo "Failed: one or more Waterwall client checks did not pass." >&2
echo "Hint: check both sides with Service control and review logs." >&2
exit 1
