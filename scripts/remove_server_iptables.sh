#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"

PORT=""

if [ -f "${CONFIG_FILE}" ]; then
  PORT="$(awk '
    $1 == "listen:" { inlisten=1; next }
    inlisten && $1 == "addr:" {
      gsub(/"/, "", $2);
      sub(/^:/, "", $2);
      print $2;
      exit
    }
  ' "${CONFIG_FILE}")"
fi

if [ -z "${PORT}" ] && [ -f "${INFO_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${INFO_FILE}"
  PORT="${listen_port:-}"
fi

if [ -z "${PORT}" ]; then
  echo "Could not determine listen port. Create server config first (${CONFIG_FILE})." >&2
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
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
    systemctl enable --now nftables >/dev/null 2>&1 || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif command -v iptables-save >/dev/null 2>&1; then
    if [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4
      echo "Saved to /etc/iptables/rules.v4"
    fi
  elif command -v service >/dev/null 2>&1; then
    service iptables save || true
  fi
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
