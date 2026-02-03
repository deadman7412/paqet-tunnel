#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"

PORT_DEFAULT="9999"
if [ -f "${INFO_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${INFO_FILE}"
  if [ -n "${listen_port:-}" ]; then
    PORT_DEFAULT="${listen_port}"
  fi
fi

read -r -p "Server listen port [${PORT_DEFAULT}]: " PORT
PORT="${PORT:-${PORT_DEFAULT}}"

if [ -z "${PORT}" ]; then
  echo "Port is required." >&2
  exit 1
fi

# Remove rules (ignore if not present)
iptables -t raw -D PREROUTING -p tcp --dport "${PORT}" -j NOTRACK 2>/dev/null || true
iptables -t raw -D OUTPUT -p tcp --sport "${PORT}" -j NOTRACK 2>/dev/null || true
iptables -t mangle -D OUTPUT -p tcp --sport "${PORT}" --tcp-flags RST RST -j DROP 2>/dev/null || true
iptables -t filter -D INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
iptables -t filter -D OUTPUT -p tcp --sport "${PORT}" -j ACCEPT 2>/dev/null || true

echo "Removed iptables rules for port ${PORT}."

# Persist rules removal
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
  if [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
    echo "Saved to /etc/iptables/rules.v4"
  fi
elif command -v service >/dev/null 2>&1; then
  service iptables save || true
fi

# Optional: remove persistence packages
read -r -p "Remove iptables persistence packages? [y/N]: " REMOVE_PKG
case "${REMOVE_PKG}" in
  y|Y)
    if command -v apt-get >/dev/null 2>&1; then
      apt-get remove -y iptables-persistent netfilter-persistent
    elif command -v dnf >/dev/null 2>&1; then
      dnf remove -y iptables-services
    elif command -v yum >/dev/null 2>&1; then
      yum remove -y iptables-services
    else
      echo "No supported package manager found. Skipping." >&2
    fi
    ;;
  *) ;;
esac
