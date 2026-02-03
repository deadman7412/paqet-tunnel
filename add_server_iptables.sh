#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"

PORT=""

if [ -f "${CONFIG_FILE}" ]; then
  PORT="$(awk -F: '/listen:/ {inlisten=1} inlisten && /addr:/ {gsub(/[ \"\t]/,\"\"); print $2; exit}' "${CONFIG_FILE}" | sed 's/^://')"
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

echo "Select OS family for persistence:"
echo "1) Debian/Ubuntu (iptables-persistent)"
echo "2) RHEL/CentOS/Alma/Rocky (iptables-services)"
read -r -p "Choose [1/2]: " OS_CHOICE

case "${OS_CHOICE}" in
  1)
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
    else
      echo "apt-get not found. Skipping package install." >&2
    fi
    ;;
  2)
    if command -v yum >/dev/null 2>&1; then
      yum install -y iptables-services
      systemctl enable --now iptables
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y iptables-services
      systemctl enable --now iptables
    else
      echo "yum/dnf not found. Skipping package install." >&2
    fi
    ;;
  *)
    echo "Invalid choice. Skipping package install." >&2
    ;;
esac

# Add required rules
iptables -t raw -A PREROUTING -p tcp --dport "${PORT}" -j NOTRACK
iptables -t raw -A OUTPUT -p tcp --sport "${PORT}" -j NOTRACK
iptables -t mangle -A OUTPUT -p tcp --sport "${PORT}" --tcp-flags RST RST -j DROP

# Optional accept rules (auto-enabled)
iptables -t filter -A INPUT -p tcp --dport "${PORT}" -j ACCEPT
iptables -t filter -A OUTPUT -p tcp --sport "${PORT}" -j ACCEPT

# Persist rules
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
  if [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
    echo "Saved to /etc/iptables/rules.v4"
  else
    echo "iptables-save available but /etc/iptables not found; skipping save." >&2
  fi
elif command -v service >/dev/null 2>&1; then
  service iptables save || true
fi

echo "Server iptables rules added for port ${PORT}."
