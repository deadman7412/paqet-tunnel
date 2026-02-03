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

add_rule() {
  local table="$1"; shift
  if iptables -t "${table}" -C "$@" 2>/dev/null; then
    return 0
  fi
  iptables -t "${table}" -A "$@"
}

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
add_rule raw PREROUTING -p tcp --dport "${PORT}" -j NOTRACK
add_rule raw OUTPUT -p tcp --sport "${PORT}" -j NOTRACK
add_rule mangle OUTPUT -p tcp --sport "${PORT}" --tcp-flags RST RST -j DROP

# Optional accept rules (auto-enabled)
add_rule filter INPUT -p tcp --dport "${PORT}" -j ACCEPT
add_rule filter OUTPUT -p tcp --sport "${PORT}" -j ACCEPT

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
