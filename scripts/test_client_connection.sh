#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
CONFIG_FILE="${PAQET_DIR}/client.yaml"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Client config not found: ${CONFIG_FILE}" >&2
  exit 1
fi

SOCKS_LISTEN=""
SOCKS_LISTEN="$(awk '
  $1 == "socks5:" { insocks=1; next }
  insocks && $1 == "-" && $2 == "listen:" { gsub(/"/, "", $3); print $3; exit }
  insocks && $1 == "listen:" { gsub(/"/, "", $2); print $2; exit }
' "${CONFIG_FILE}")"

if [ -z "${SOCKS_LISTEN}" ]; then
  SOCKS_LISTEN="127.0.0.1:1080"
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for the test." >&2
  exit 1
fi

echo "Testing SOCKS5 proxy at ${SOCKS_LISTEN}..."

# Try HTTPS first
if curl -fsSL --connect-timeout 5 --max-time 10 https://httpbin.org/ip --proxy "socks5h://${SOCKS_LISTEN}" >/dev/null; then
  echo "Success: proxy is working (HTTPS)."
  exit 0
fi

# Fallback to HTTP if SSL fails (helps diagnose TLS issues)
if curl -fsSL --connect-timeout 5 --max-time 10 http://httpbin.org/ip --proxy "socks5h://${SOCKS_LISTEN}" >/dev/null; then
  echo "Success: proxy is working (HTTP)."
  echo "Note: HTTPS failed; check TLS/SSL path or packet loss."
  exit 0
fi

echo "Failed: proxy test did not succeed." >&2
echo "Hint: If you see SSL errors/timeouts, try lowering MTU to 1200 via the Change MTU menu option." >&2
exit 1
