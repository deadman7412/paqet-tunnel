#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
CONFIG_FILE="${PAQET_DIR}/client.yaml"

install_pkg_apt() {
  local ok=0
  apt-get update -y
  for pkg in proxychains4 proxychains-ng; do
    if apt-get install -y "${pkg}"; then
      ok=1
      break
    fi
  done
  if [ "${ok}" -ne 1 ]; then
    echo "Failed to install proxychains via apt-get." >&2
    exit 1
  fi
}

install_pkg_dnf() {
  local ok=0
  for pkg in proxychains-ng proxychains; do
    if dnf install -y "${pkg}"; then
      ok=1
      break
    fi
  done
  if [ "${ok}" -ne 1 ]; then
    echo "Failed to install proxychains via dnf." >&2
    exit 1
  fi
}

install_pkg_yum() {
  local ok=0
  for pkg in proxychains-ng proxychains; do
    if yum install -y "${pkg}"; then
      ok=1
      break
    fi
  done
  if [ "${ok}" -ne 1 ]; then
    echo "Failed to install proxychains via yum." >&2
    exit 1
  fi
}

if command -v apt-get >/dev/null 2>&1; then
  install_pkg_apt
elif command -v dnf >/dev/null 2>&1; then
  install_pkg_dnf
elif command -v yum >/dev/null 2>&1; then
  install_pkg_yum
else
  echo "No supported package manager found (apt-get/dnf/yum)." >&2
  exit 1
fi

SOCKS_LISTEN=""
if [ -f "${CONFIG_FILE}" ]; then
  SOCKS_LISTEN="$(awk '
    $1 == "socks5:" { insocks=1; next }
    insocks && $1 == "-" && $2 == "listen:" { gsub(/\"/, "", $3); print $3; exit }
    insocks && $1 == "listen:" { gsub(/\"/, "", $2); print $2; exit }
  ' "${CONFIG_FILE}")"
fi

if [ -z "${SOCKS_LISTEN}" ]; then
  SOCKS_LISTEN="127.0.0.1:1080"
  echo "Warning: ${CONFIG_FILE} not found or SOCKS listen missing. Using default ${SOCKS_LISTEN}." >&2
fi

SOCKS_HOST="${SOCKS_LISTEN%:*}"
SOCKS_PORT="${SOCKS_LISTEN##*:}"
if [ -z "${SOCKS_HOST}" ] || [ "${SOCKS_HOST}" = "${SOCKS_PORT}" ]; then
  SOCKS_HOST="127.0.0.1"
fi
if ! [[ "${SOCKS_PORT}" =~ ^[0-9]+$ ]]; then
  SOCKS_PORT="1080"
fi

PROXYCHAINS_CONF=""
if [ -f /etc/proxychains4.conf ]; then
  PROXYCHAINS_CONF="/etc/proxychains4.conf"
elif [ -f /etc/proxychains.conf ]; then
  PROXYCHAINS_CONF="/etc/proxychains.conf"
else
  PROXYCHAINS_CONF="/etc/proxychains4.conf"
  cat <<'CONF_EOF' > "${PROXYCHAINS_CONF}"
# proxychains4 config created by paqet-tunnel
strict_chain
proxy_dns

tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
# add proxies here
CONF_EOF
fi

if ! grep -q '^\[ProxyList\]' "${PROXYCHAINS_CONF}"; then
  echo "" >> "${PROXYCHAINS_CONF}"
  echo "[ProxyList]" >> "${PROXYCHAINS_CONF}"
fi

TMP_FILE="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^# paqet-tunnel start$/ {skip=1; next}
  /^# paqet-tunnel end$/ {skip=0; next}
  skip==1 {next}
  # Comment out default Tor proxy entries if present
  /^socks[45][[:space:]]+127\.0\.0\.1[[:space:]]+9050([[:space:]]|$)/ {
    if ($0 ~ /^#/) { print; next }
    print "# " $0; next
  }
  {print}
' "${PROXYCHAINS_CONF}" > "${TMP_FILE}"
cat "${TMP_FILE}" > "${PROXYCHAINS_CONF}"
rm -f "${TMP_FILE}"

cat <<PROXY_EOF >> "${PROXYCHAINS_CONF}"
# paqet-tunnel start
socks5 ${SOCKS_HOST} ${SOCKS_PORT}
# paqet-tunnel end
PROXY_EOF

echo "proxychains installed and configured at ${PROXYCHAINS_CONF}."
echo "SOCKS5 target: ${SOCKS_HOST}:${SOCKS_PORT}"
echo "Example: proxychains4 curl https://httpbin.org/ip"
